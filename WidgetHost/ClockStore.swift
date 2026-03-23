import AppKit
import Combine
import AVFoundation

enum ClockMode: String, CaseIterable {
    case stopwatch = "Stopwatch"
    case countdown = "Timer"
    case pomodoro  = "Pomodoro"
}

enum PomodoroPhase {
    case work, shortBreak, longBreak

    var label: String {
        switch self {
        case .work:       return "Focus Time"
        case .shortBreak: return "Short Break"
        case .longBreak:  return "Long Break"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .work:       return 25 * 60
        case .shortBreak: return  5 * 60
        case .longBreak:  return 15 * 60
        }
    }
}

class ClockStore: ObservableObject {
    @Published var mode: ClockMode       = .stopwatch
    @Published var isRunning: Bool       = false

    // Stopwatch
    @Published var elapsed: TimeInterval = 0

    // Countdown / Pomodoro
    @Published var remaining: TimeInterval      = 25 * 60
    @Published var countdownDuration: TimeInterval = 25 * 60

    // Pomodoro
    @Published var pomodoroPhase: PomodoroPhase = .work
    @Published var pomodoroSession: Int         = 1

    private var timer:       Timer?
    private var startDate:   Date?
    private var accumulated: TimeInterval = 0

    // MARK: - Public Controls

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        accumulated += Date().timeIntervalSince(startDate ?? Date())
        startDate = nil
        timer?.invalidate()
        timer = nil
        updateDisplay()
    }

    func reset() {
        let wasRunning = isRunning
        pause()
        accumulated = 0
        switch mode {
        case .stopwatch:
            elapsed = 0
        case .countdown:
            remaining = countdownDuration
        case .pomodoro:
            pomodoroPhase   = .work
            pomodoroSession = 1
            remaining       = PomodoroPhase.work.duration
        }
        if wasRunning && mode == .pomodoro { start() }
    }

    func setMode(_ newMode: ClockMode) {
        let changing = mode != newMode
        if changing { pause() }
        mode = newMode
        accumulated = 0
        switch newMode {
        case .stopwatch: elapsed   = 0
        case .countdown: remaining = countdownDuration
        case .pomodoro:
            pomodoroPhase   = .work
            pomodoroSession = 1
            remaining       = PomodoroPhase.work.duration
        }
    }

    func setCountdownDuration(hours: Int, minutes: Int) {
        let dur = TimeInterval(hours * 3600 + minutes * 60)
        countdownDuration = dur
        if !isRunning { remaining = dur; accumulated = 0 }
    }

    func skipPomodoroPhase() {
        guard mode == .pomodoro else { return }
        advancePomodoro(autoStart: false)
    }

    // MARK: - Derived

    var displayTime: String {
        formatTime(mode == .stopwatch ? elapsed : remaining)
    }

    var progress: Double {
        switch mode {
        case .stopwatch: return 0
        case .countdown:
            return countdownDuration > 0 ? 1 - remaining / countdownDuration : 0
        case .pomodoro:
            return 1 - remaining / pomodoroPhase.duration
        }
    }

    func formatTime(_ t: TimeInterval) -> String {
        let t = max(0, t)
        let h = Int(t) / 3600
        let m = Int(t) % 3600 / 60
        let s = Int(t) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Private

    private func tick() {
        let live = accumulated + Date().timeIntervalSince(startDate ?? Date())
        switch mode {
        case .stopwatch:
            elapsed = live

        case .countdown:
            remaining = max(0, countdownDuration - live)
            if remaining == 0 { pause(); chime() }

        case .pomodoro:
            remaining = max(0, pomodoroPhase.duration - live)
            if remaining == 0 { advancePomodoro(autoStart: true) }
        }
    }

    private func updateDisplay() {
        let t = accumulated
        switch mode {
        case .stopwatch: elapsed   = t
        case .countdown: remaining = max(0, countdownDuration - t)
        case .pomodoro:  remaining = max(0, pomodoroPhase.duration - t)
        }
    }

    private func advancePomodoro(autoStart: Bool) {
        pause()
        switch pomodoroPhase {
        case .work:
            pomodoroPhase = pomodoroSession % 4 == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            pomodoroSession += 1
            pomodoroPhase = .work
        }
        accumulated = 0
        remaining = pomodoroPhase.duration
        chime()
        if autoStart { start() }
    }

    // MARK: - Ringtone

    private let chimeEngine = AVAudioEngine()
    private let chimePlayer = AVAudioPlayerNode()
    private var chimeEngineReady = false

    private func prepareChimeEngine() {
        guard !chimeEngineReady else { return }
        chimeEngine.attach(chimePlayer)
        chimeEngine.connect(chimePlayer, to: chimeEngine.mainMixerNode, format: nil)
        try? chimeEngine.start()
        chimeEngineReady = true
    }

    private func chime() {
        prepareChimeEngine()

        let sampleRate: Double = 44100
        // Ascending arpeggio: C5 → E5 → G5 → C6, each note fades with exponential decay
        // (frequency Hz, start seconds, duration seconds, amplitude)
        let notes: [(Double, Double, Double, Double)] = [
            (523.25, 0.00, 0.55, 0.50),   // C5
            (659.25, 0.20, 0.55, 0.45),   // E5
            (783.99, 0.40, 0.65, 0.45),   // G5
            (1046.5, 0.62, 0.90, 0.38),   // C6
        ]

        let totalDuration = notes.map { $0.1 + $0.2 }.max() ?? 1.5
        let totalFrames   = AVAudioFrameCount(totalDuration * sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return }
        buffer.frameLength = totalFrames

        let L = buffer.floatChannelData![0]
        let R = buffer.floatChannelData![1]
        for i in 0..<Int(totalFrames) { L[i] = 0; R[i] = 0 }

        for (freq, startSec, duration, amp) in notes {
            let startFrame = Int(startSec * sampleRate)
            let noteFrames = Int(duration * sampleRate)
            for i in 0..<noteFrames {
                let t   = Double(i) / sampleRate
                let env = exp(-t * 3.5)                              // decay envelope
                let harmonics = sin(2 * .pi * freq * t)             // fundamental
                             + sin(4 * .pi * freq * t) * 0.25       // 2nd harmonic (body)
                             + sin(8 * .pi * freq * t) * 0.06       // 4th harmonic (sparkle)
                let val = Float(harmonics * env * amp)
                let fi  = startFrame + i
                if fi < Int(totalFrames) { L[fi] += val; R[fi] += val }
            }
        }

        chimePlayer.stop()
        chimePlayer.scheduleBuffer(buffer, completionHandler: nil)
        chimePlayer.play()
    }
}
