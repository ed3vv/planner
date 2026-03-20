import AppKit
import Combine

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

    private func chime() {
        NSSound(named: "Glass")?.play()
    }
}
