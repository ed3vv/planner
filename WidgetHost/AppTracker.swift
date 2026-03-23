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
    var events: [AppEvent]
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

@MainActor
class AppTracker: ObservableObject {
    @Published var currentAppName: String   = ""
    @Published var currentAppIcon: NSImage? = nil
    @Published var focusScore: Double       = 0
    @Published var todayUsage: [AppUsage]   = []
    @Published var isTracking: Bool         = false
    @Published var history: [DailyRecord]   = []
    @Published var recaps: [SessionRecap]   = []
    @Published var lastRecap: SessionRecap? = nil
    @Published var timerStartTime: Date     = Date()

    private var isTrackingEnabled      = false
    private var sessionStart: Date     = Date()
    private var sessionFlushedDuration: TimeInterval = 0  // time already added to accumulated in current session
    private var currentBundleID        = ""
    private var accumulated: [String: (name: String, icon: NSImage?, duration: TimeInterval)] = [:]
    private var flushTimer: Timer?

    // Per-session event log
    private var currentEventLog: [AppEvent] = []

    // Browser tracking
    private var browserPollTimer: Timer?
    private var currentURL             = ""
    private var currentBrowserBundleID = ""
    private var currentBrowserIcon: NSImage? = nil

    // User-defined category overrides (bundleID or "web:domain" → AppCategory)
    private var userCategories: [String: AppCategory] = [:]
    private let userCategoriesKey = "focusapp_user_categories_v1"

    // History persistence
    private var dailyRecords: [String: DailyRecord] = [:]
    private var currentDayKey     = ""
    private var timerSessionCount = 0
    private let historyKey = "focusapp_history_v1"
    private let recapsKey  = "focusapp_recaps_v1"

    static let dayFmtPublic: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private var todayKey: String { Self.dayFmtPublic.string(from: Date()) }

    // MARK: - App / domain categorisation

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
    private let productiveDomains: Set<String> = [
        "github.com", "gitlab.com", "bitbucket.org",
        "stackoverflow.com", "stackexchange.com",
        "developer.apple.com", "docs.swift.org",
        "figma.com", "notion.so", "linear.app",
        "claude.ai", "chatgpt.com",
        "google.com", "google.co.uk",
        "docs.google.com", "drive.google.com",
        "wikipedia.org", "medium.com",
    ]
    private let distractingDomains: Set<String> = [
        "youtube.com", "youtu.be",
        "netflix.com", "twitch.tv", "primevideo.com", "disneyplus.com",
        "reddit.com", "old.reddit.com",
        "twitter.com", "x.com",
        "instagram.com", "facebook.com", "threads.net",
        "tiktok.com", "snapchat.com",
        "discord.com", "9gag.com",
    ]

    // Browser bundle ID → AppleScript application name
    private let browserScriptName: [String: String] = [
        "com.apple.Safari":                  "Safari",
        "com.apple.SafariTechnologyPreview": "Safari Technology Preview",
        "com.google.Chrome":                 "Google Chrome",
        "com.google.Chrome.canary":          "Google Chrome Canary",
        "com.microsoft.edgemac":             "Microsoft Edge",
        "com.brave.Browser":                 "Brave Browser",
        "com.operasoftware.Opera":           "Opera",
        "org.mozilla.firefox":               "Firefox",
    ]

    init() {
        loadHistory()
        loadRecaps()
        loadUserCategories()
        observeAppSwitches()
        startFlushTimer()
    }

    // MARK: - Public: category overrides

    func setCategory(_ cat: AppCategory, for bundleID: String) {
        userCategories[bundleID] = cat
        if let data = try? JSONEncoder().encode(userCategories) {
            UserDefaults.standard.set(data, forKey: userCategoriesKey)
        }
        rebuildStats()
    }

    func resetCategory(for bundleID: String) {
        userCategories.removeValue(forKey: bundleID)
        if let data = try? JSONEncoder().encode(userCategories) {
            UserDefaults.standard.set(data, forKey: userCategoriesKey)
        }
        rebuildStats()
    }

    func userCategory(for bundleID: String) -> AppCategory? {
        userCategories[bundleID]
    }

    // MARK: - Enable / Disable

    func enableTracking() {
        guard !isTrackingEnabled else { return }
        let today = todayKey
        if !currentDayKey.isEmpty && currentDayKey != today {
            accumulated = [:]; timerSessionCount = 0; focusScore = 0; todayUsage = []
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
        stopBrowserPolling()
        isTrackingEnabled = false
        isTracking        = false
        currentBundleID   = ""
        currentAppName    = ""
        currentAppIcon    = nil
        currentURL        = ""
        finaliseRecap()
        saveTodayRecord()
        FirebaseManager.shared.updatePresence(focusScore: focusScore, currentApp: nil, isOnline: false)
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

    var todayRecord: DailyRecord {
        effectiveHistory.first { $0.dayKey == todayKey }
            ?? DailyRecord(dayKey: todayKey, focusScore: focusScore,
                           productiveSeconds: 0, distractingSeconds: 0,
                           totalSeconds: 0, sessionCount: 0)
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

    // Synthesised event for the currently running app (not yet committed to currentEventLog)
    var liveEvent: AppEvent? {
        guard isTrackingEnabled, !currentBundleID.isEmpty,
              browserScriptName[currentBundleID] == nil else { return nil }
        let dur = Date().timeIntervalSince(sessionStart)
        guard dur > 1 else { return nil }
        return AppEvent(bundleID: currentBundleID, name: currentAppName,
                        category: category(for: currentBundleID),
                        startTime: sessionStart, duration: dur)
    }

    var todayTimeline: [AppEvent] {
        let key = todayKey
        let saved = recaps.filter { $0.dayKey == key }.flatMap(\.events)
        var all = saved + currentEventLog
        if let live = liveEvent { all.append(live) }
        return all.sorted { $0.startTime < $1.startTime }
    }

    var todaySessions: [(events: [AppEvent], start: Date, end: Date)] {
        let key = todayKey
        var result: [(events: [AppEvent], start: Date, end: Date)] = []
        for recap in recaps.filter({ $0.dayKey == key }) {
            result.append((recap.events, recap.startedAt, recap.endedAt))
        }
        if isTracking {
            var events = currentEventLog
            if let live = liveEvent { events.append(live) }
            if !events.isEmpty {
                let end = events.map { $0.startTime.addingTimeInterval($0.duration) }.max() ?? Date()
                result.append((events, timerStartTime, max(end, Date())))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    // MARK: - Private: session management

    private func startSession(for app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? "unknown"
        sessionStart          = Date()
        sessionFlushedDuration = 0

        if let scriptName = browserScriptName[bundleID] {
            // Browser: set placeholder, then async-fetch actual URL
            currentBrowserBundleID = bundleID
            currentBrowserIcon     = app.icon
            currentAppIcon         = app.icon
            currentBundleID        = bundleID
            currentAppName         = app.localizedName ?? "Browser"
            currentURL             = ""

            let capturedBundleID = bundleID
            fetchBrowserURL(scriptName: scriptName) { [weak self] url in
                guard let self, self.currentBrowserBundleID == capturedBundleID,
                      self.isTrackingEnabled else { return }
                guard let url, let domain = self.extractDomain(from: url) else { return }
                let elapsed = Date().timeIntervalSince(self.sessionStart)
                if elapsed < 2 {
                    self.currentBundleID = "web:\(domain)"
                    self.currentAppName  = domain
                } else {
                    self.endCurrentSession()
                    self.currentBundleID        = "web:\(domain)"
                    self.currentAppName         = domain
                    self.sessionStart           = Date()
                    self.sessionFlushedDuration = 0
                }
                self.currentURL = domain
            }
            startBrowserPolling(scriptName: scriptName, bundleID: bundleID)

        } else {
            stopBrowserPolling()
            currentBrowserBundleID = ""
            currentURL             = ""
            currentBundleID        = bundleID
            currentAppName         = app.localizedName ?? "Unknown"
            currentAppIcon         = app.icon
        }
    }

    private func endCurrentSession() {
        guard !currentBundleID.isEmpty else { return }
        // Skip browser placeholder entries (URL hasn't loaded yet — bundle ID is the
        // browser's own ID, not a "web:domain" key). Prevents "Safari" / "Google Chrome"
        // appearing as spurious short entries alongside the real domain entries.
        guard browserScriptName[currentBundleID] == nil else { return }
        let totalDur = Date().timeIntervalSince(sessionStart)
        let newDur   = totalDur - sessionFlushedDuration   // un-flushed portion
        // Add only the portion not yet flushed to accumulated
        if newDur > 0.5 {
            let prev = accumulated[currentBundleID]
            let icon: NSImage? = prev?.icon
                ?? (currentBundleID.hasPrefix("web:") ? currentBrowserIcon : iconForBundle(currentBundleID))
            accumulated[currentBundleID] = (currentAppName, icon, (prev?.duration ?? 0) + newDur)
        }
        // Event spans the full session from true sessionStart (not the last flush point)
        if totalDur > 0.5 {
            let cat = category(for: currentBundleID)
            currentEventLog.append(AppEvent(bundleID: currentBundleID, name: currentAppName,
                                            category: cat, startTime: sessionStart, duration: totalDur))
        }
        sessionFlushedDuration = 0
        rebuildStats()
    }

    // MARK: - Private: browser polling (via osascript subprocess — thread-safe)

    private func startBrowserPolling(scriptName: String, bundleID: String) {
        stopBrowserPolling()
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            self?.pollBrowserURL(scriptName: scriptName, bundleID: bundleID)
        }
        RunLoop.main.add(timer, forMode: .common)
        browserPollTimer = timer
    }

    private func stopBrowserPolling() {
        browserPollTimer?.invalidate()
        browserPollTimer = nil
    }

    private func pollBrowserURL(scriptName: String, bundleID: String) {
        guard isTrackingEnabled, currentBrowserBundleID == bundleID else { return }
        fetchBrowserURL(scriptName: scriptName) { [weak self] url in
            guard let self, self.isTrackingEnabled,
                  self.currentBrowserBundleID == bundleID else { return }
            guard let url, let domain = self.extractDomain(from: url),
                  domain != self.currentURL else { return }
            self.endCurrentSession()
            self.currentBundleID        = "web:\(domain)"
            self.currentAppName         = domain
            self.currentAppIcon         = self.currentBrowserIcon
            self.sessionStart           = Date()
            self.sessionFlushedDuration = 0
            self.currentURL      = domain
        }
    }

    /// Fetches the active tab URL from a browser via NSAppleScript.
    /// NSAppleScript is main-thread only per Apple docs — this schedules async on main
    /// so the caller isn't blocked. The ~30ms execution at 4s intervals is imperceptible.
    /// Requires `com.apple.security.automation.apple-events` entitlement + user Automation grant.
    private func fetchBrowserURL(scriptName: String, completion: @escaping (String?) -> Void) {
        guard scriptName != "Firefox" else { completion(nil); return }

        let src: String
        switch scriptName {
        case "Safari", "Safari Technology Preview":
            src = "tell application \"\(scriptName)\" to if (count of windows) > 0 then return URL of current tab of front window"
        default:
            // Chrome, Edge, Brave, Opera all share the same AppleScript surface.
            src = "tell application \"\(scriptName)\" to if (count of windows) > 0 then return URL of active tab of front window"
        }

        // Must execute on main thread; async so we don't block the caller.
        DispatchQueue.main.async {
            var err: NSDictionary?
            let result = NSAppleScript(source: src)?.executeAndReturnError(&err)
            if err != nil {
                completion(nil)
            } else if let str = result?.stringValue, !str.isEmpty, str.contains("://") {
                completion(str)
            } else {
                completion(nil)
            }
        }
    }

    private func extractDomain(from urlString: String) -> String? {
        // Handle Firefox window title case (not a URL)
        if !urlString.contains("://") { return nil }
        guard let url  = URL(string: urlString),
              let host = url.host, !host.isEmpty else { return nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return domain.isEmpty ? nil : domain
    }

    // MARK: - Private: history + recap

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
        FirebaseManager.shared.syncDailyRecord(dailyRecords[key]!)
    }

    private func saveRecaps() {
        let trimmed = Array(recaps.prefix(200))
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

    // MARK: - Private: infra

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
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard self?.isTrackingEnabled == true else { return }
            DispatchQueue.main.async { self?.flushCurrentSession(); self?.saveTodayRecord() }
        }
        RunLoop.main.add(flushTimer!, forMode: .common)
    }

    private func flushCurrentSession() {
        // Accumulate elapsed time without ending the session or creating an event.
        // Events are only written in endCurrentSession() on real app switches / stop.
        guard !currentBundleID.isEmpty,
              browserScriptName[currentBundleID] == nil else { return }
        let totalDur = Date().timeIntervalSince(sessionStart)
        let newDur   = totalDur - sessionFlushedDuration
        guard newDur > 0.5 else { return }
        let prev = accumulated[currentBundleID]
        let icon: NSImage? = prev?.icon
            ?? (currentBundleID.hasPrefix("web:") ? currentBrowserIcon : iconForBundle(currentBundleID))
        accumulated[currentBundleID] = (currentAppName, icon, (prev?.duration ?? 0) + newDur)
        sessionFlushedDuration = totalDur   // remember what we've already counted
        rebuildStats()
    }

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
        // Broadcast live presence so friends can see your focus score + current app
        FirebaseManager.shared.updatePresence(
            focusScore: focusScore,
            currentApp: currentAppName.isEmpty ? nil : currentAppName,
            isOnline:   isTrackingEnabled
        )
    }

    private func iconForBundle(_ id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func category(for bundleID: String) -> AppCategory {
        // User overrides take precedence over built-in defaults.
        if let override = userCategories[bundleID] { return override }
        if bundleID.hasPrefix("web:") {
            let domain = String(bundleID.dropFirst(4))
            if productiveDomains.contains(domain)  { return .productive }
            if distractingDomains.contains(domain) { return .distracting }
            return .neutral
        }
        if productiveApps.contains(bundleID)   { return .productive }
        if distractingApps.contains(bundleID)  { return .distracting }
        return .neutral
    }

    private func loadUserCategories() {
        guard let data = UserDefaults.standard.data(forKey: userCategoriesKey),
              let saved = try? JSONDecoder().decode([String: AppCategory].self, from: data) else { return }
        userCategories = saved
    }
}
