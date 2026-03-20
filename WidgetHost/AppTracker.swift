import AppKit

enum AppCategory: String, Codable {
    case productive, neutral, distracting

    var label: String {
        switch self {
        case .productive:  return "Productive"
        case .neutral:     return "Neutral"
        case .distracting: return "Distracting"
        }
    }
}

struct AppUsage: Identifiable {
    let id = UUID()
    let bundleID: String
    let name: String
    let icon: NSImage?
    var duration: TimeInterval
    let category: AppCategory
}

// One app-switch event in a session (icon looked up at render time via bundleID)
struct AppEvent: Codable, Identifiable {
    var id: UUID = UUID()
    var bundleID: String
    var name: String
    var category: AppCategory
    var startTime: Date
    var duration: TimeInterval
}

struct SessionRecap: Codable, Identifiable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date
    var events: [AppEvent]    // chronological
    var focusScore: Double
    var productiveSeconds: TimeInterval
    var totalSeconds: TimeInterval

    var dayKey: String { AppTracker.dayFmtPublic.string(from: startedAt) }
}

struct DailyRecord: Codable, Identifiable {
    var id: String { dayKey }
    var dayKey: String
    var focusScore: Double
    var productiveSeconds: TimeInterval
    var distractingSeconds: TimeInterval
    var totalSeconds: TimeInterval
    var sessionCount: Int
}

class AppTracker: ObservableObject {
    @Published var currentAppName: String   = ""
    @Published var currentAppIcon: NSImage? = nil
    @Published var focusScore: Double       = 0
    @Published var todayUsage: [AppUsage]   = []
    @Published var isTracking: Bool         = false
    @Published var history: [DailyRecord]   = []
    @Published var recaps: [SessionRecap]   = []   // newest first, all sessions ever
    @Published var lastRecap: SessionRecap? = nil

    private var isTrackingEnabled  = false
    private var sessionStart: Date = Date()
    private var currentBundleID    = ""
    private var accumulated: [String: (name: String, icon: NSImage?, duration: TimeInterval)] = [:]
    private var timer: Timer?

    // Per-timer-session event log
    private var currentEventLog: [AppEvent] = []
    private var timerStartTime: Date        = Date()

    // History
    private var dailyRecords: [String: DailyRecord] = [:]
    private var currentDayKey    = ""
    private var timerSessionCount = 0
    private let historyKey  = "focusapp_history_v1"
    private let recapsKey   = "focusapp_recaps_v1"

    static let dayFmtPublic: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private var todayKey: String { Self.dayFmtPublic.string(from: Date()) }

    private let productiveApps: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.sublimetext.4",
        "com.jetbrains.intellij.ce", "com.jetbrains.WebStorm", "com.jetbrains.PyCharm",
        "com.apple.Terminal", "com.googlecode.iterm2", "com.apple.Notes",
        "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint",
        "com.apple.Pages", "com.apple.Numbers", "com.apple.Keynote",
        "com.figma.Desktop", "com.notion.id", "com.linear.linear",
        "com.tinyspeck.slackmacgap", "com.github.GitHubDesktop", "com.readdle.PDF-Expert-5",
    ]
    private let distractingApps: Set<String> = [
        "com.apple.TV", "com.hnc.Discord", "com.twitter.twitter-mac",
        "com.facebook.archon", "org.videolan.vlc", "com.apple.iChat",
    ]

    init() {
        loadHistory()
        loadRecaps()
        observeAppSwitches()
        startFlushTimer()
    }

    // MARK: - Enable / Disable

    func enableTracking() {
        guard !isTrackingEnabled else { return }
        let today = todayKey
        if !currentDayKey.isEmpty && currentDayKey != today {
            accumulated = []; timerSessionCount = 0; focusScore = 0; todayUsage = []
        }
        currentDayKey     = today
        timerSessionCount += 1
        currentEventLog   = []
        timerStartTime    = Date()
        isTrackingEnabled = true
        isTracking        = true
        if let app = NSWorkspace.shared.frontmostApplication { startSession(for: app) }
    }

    func disableTracking() {
        guard isTrackingEnabled else { return }
        endCurrentSession()
        isTrackingEnabled = false
        isTracking        = false
        currentBundleID   = ""
        currentAppName    = ""
        currentAppIcon    = nil
        finaliseRecap()
        saveTodayRecord()
    }

    // MARK: - Computed averages

    var avgFocusScore: Double {
        let r = effectiveHistory; guard !r.isEmpty else { return 0 }
        return r.map(\.focusScore).reduce(0, +) / Double(r.count)
    }
    var avgFocusedTimePerDay: TimeInterval {
        let r = effectiveHistory; guard !r.isEmpty else { return 0 }
        return r.map(\.productiveSeconds).reduce(0, +) / Double(r.count)
    }
    var avgSessionLength: TimeInterval {
        let r = effectiveHistory
        let s = r.map(\.sessionCount).reduce(0, +); guard s > 0 else { return 0 }
        return r.map(\.productiveSeconds).reduce(0, +) / Double(s)
    }

    var last7Days: [DailyRecord] {
        let cal = Calendar.current
        return (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -(6 - offset), to: Date()) else { return nil }
            let key = Self.dayFmtPublic.string(from: date)
            return effectiveHistory.first { $0.dayKey == key }
                ?? DailyRecord(dayKey: key, focusScore: 0, productiveSeconds: 0,
                               distractingSeconds: 0, totalSeconds: 0, sessionCount: 0)
        }
    }

    /// All events for today from all saved recaps, chronological.
    var todayTimeline: [AppEvent] {
        let key = todayKey
        let saved = recaps.filter { $0.dayKey == key }.flatMap(\.events)
        return (saved + currentEventLog).sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Private

    private func finaliseRecap() {
        guard !currentEventLog.isEmpty else { return }
        let prod  = currentEventLog.filter { $0.category == .productive }.reduce(0.0) { $0 + $1.duration }
        let total = currentEventLog.reduce(0.0) { $0 + $1.duration }
        let recap = SessionRecap(startedAt: timerStartTime, endedAt: Date(),
                                 events: currentEventLog, focusScore: focusScore,
                                 productiveSeconds: prod, totalSeconds: total)
        recaps.insert(recap, at: 0)
        lastRecap = recap
        saveRecaps()
    }

    private var effectiveHistory: [DailyRecord] {
        var records = dailyRecords
        let total = todayUsage.reduce(0.0) { $0 + $1.duration }
        if total > 0 {
            let prod = todayUsage.filter { $0.category == .productive }.reduce(0.0) { $0 + $1.duration }
            let dist = todayUsage.filter { $0.category == .distracting }.reduce(0.0) { $0 + $1.duration }
            let key  = todayKey
            let sess = max(timerSessionCount, records[key]?.sessionCount ?? 0)
            records[key] = DailyRecord(dayKey: key, focusScore: focusScore,
                                       productiveSeconds: prod, distractingSeconds: dist,
                                       totalSeconds: total, sessionCount: max(sess, 1))
        }
        return Array(records.values)
    }

    private func saveTodayRecord() {
        let key   = currentDayKey.isEmpty ? todayKey : currentDayKey
        let total = todayUsage.reduce(0.0) { $0 + $1.duration }
        guard total > 0 else { return }
        let prod = todayUsage.filter { $0.category == .productive }.reduce(0.0) { $0 + $1.duration }
        let dist = todayUsage.filter { $0.category == .distracting }.reduce(0.0) { $0 + $1.duration }
        dailyRecords[key] = DailyRecord(dayKey: key, focusScore: focusScore,
                                        productiveSeconds: prod, distractingSeconds: dist,
                                        totalSeconds: total, sessionCount: timerSessionCount)
        if let data = try? JSONEncoder().encode(dailyRecords) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
        history = dailyRecords.values.sorted { $0.dayKey > $1.dayKey }
    }

    private func saveRecaps() {
        let trimmed = Array(recaps.prefix(200))   // cap storage
        recaps = trimmed
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: recapsKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let saved = try? JSONDecoder().decode([String: DailyRecord].self, from: data) else { return }
        dailyRecords = saved
        history = saved.values.sorted { $0.dayKey > $1.dayKey }
    }

    private func loadRecaps() {
        guard let data = UserDefaults.standard.data(forKey: recapsKey),
              let saved = try? JSONDecoder().decode([SessionRecap].self, from: data) else { return }
        recaps    = saved
        lastRecap = saved.first
    }

    private func observeAppSwitches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard self?.isTrackingEnabled == true else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.endCurrentSession()
            self?.startSession(for: app)
        }
    }

    private func startFlushTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard self?.isTrackingEnabled == true else { return }
            DispatchQueue.main.async { self?.flushCurrentSession(); self?.saveTodayRecord() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func startSession(for app: NSRunningApplication) {
        currentBundleID = app.bundleIdentifier ?? "unknown"
        currentAppName  = app.localizedName ?? "Unknown"
        currentAppIcon  = app.icon
        sessionStart    = Date()
    }

    private func endCurrentSession() {
        guard !currentBundleID.isEmpty else { return }
        let dur = Date().timeIntervalSince(sessionStart)
        guard dur > 0.5 else { return }
        let prev = accumulated[currentBundleID]
        accumulated[currentBundleID] = (currentAppName, prev?.icon ?? iconForBundle(currentBundleID), (prev?.duration ?? 0) + dur)
        let cat = category(for: currentBundleID)
        currentEventLog.append(AppEvent(bundleID: currentBundleID, name: currentAppName,
                                        category: cat, startTime: sessionStart, duration: dur))
        rebuildStats()
    }

    private func flushCurrentSession() { endCurrentSession(); sessionStart = Date() }

    private func rebuildStats() {
        todayUsage = accumulated.map { bundleID, val in
            AppUsage(bundleID: bundleID, name: val.name, icon: val.icon,
                     duration: val.duration, category: category(for: bundleID))
        }.sorted { $0.duration > $1.duration }
        let total = todayUsage.reduce(0.0) { $0 + $1.duration }
        guard total > 0 else { return }
        let prod = todayUsage.filter { $0.category == .productive }.reduce(0.0) { $0 + $1.duration }
        let dist = todayUsage.filter { $0.category == .distracting }.reduce(0.0) { $0 + $1.duration }
        focusScore = max(0, min(100, (prod - dist * 0.5) / total * 100))
    }

    private func iconForBundle(_ id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func category(for bundleID: String) -> AppCategory {
        if productiveApps.contains(bundleID)  { return .productive }
        if distractingApps.contains(bundleID) { return .distracting }
        return .neutral
    }
}
