import SwiftUI
import AppKit

extension AppCategory {
    var color: Color {
        switch self {
        case .productive:  return DS.C.green
        case .neutral:     return DS.C.accent
        case .distracting: return DS.C.red
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var appTracker: AppTracker

    var totalTime: TimeInterval { appTracker.todayUsage.reduce(0) { $0 + $1.duration } }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Today score summary
                HStack(alignment: .center, spacing: DS.Space.lg) {
                    ZStack {
                        Circle()
                            .stroke(DS.C.border, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: appTracker.focusScore / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.6), value: appTracker.focusScore)
                        Text("\(Int(appTracker.focusScore))")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DS.C.textPrimary)
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(statusText)
                            .font(DS.T.body())
                            .foregroundStyle(DS.C.textPrimary)
                        HStack(spacing: DS.Space.sm) {
                            StatPill(label: "focus",      time: productiveTime, color: DS.C.green)
                            StatPill(label: "distracted", time: distractingTime, color: DS.C.red)
                        }
                    }

                    Spacer()
                }
                .padding(DS.Space.lg)

                DSDivider()

                // Trends
                TrendsSection()
                    .environmentObject(appTracker)

                DSDivider()

                // Last session recap
                if let recap = appTracker.lastRecap {
                    TimelineSection(title: "Last session", subtitle: recapSubtitle(recap),
                                    events: recap.events)
                    DSDivider()
                }

                // Today's full timeline
                let timeline = appTracker.todayTimeline
                if !timeline.isEmpty {
                    TimelineSection(title: "Today's timeline", subtitle: nil, events: timeline)
                    DSDivider()
                }

                // Currently tracking indicator
                if !appTracker.currentAppName.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        Circle().fill(DS.C.green).frame(width: 6, height: 6)
                        if let icon = appTracker.currentAppIcon {
                            Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                        }
                        Text(appTracker.currentAppName)
                            .font(DS.T.caption())
                            .foregroundStyle(DS.C.textMuted)
                        Spacer()
                        Text("now")
                            .font(DS.T.caption())
                            .foregroundStyle(DS.C.textFaint)
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.sm)
                    DSDivider()
                }

                // App usage totals
                if appTracker.todayUsage.isEmpty {
                    Text(appTracker.isTracking
                         ? "Tracking — keep working"
                         : "Start a timer to begin tracking")
                        .font(DS.T.body())
                        .foregroundStyle(DS.C.textMuted)
                        .padding(DS.Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appTracker.todayUsage) { usage in
                        AppRow(usage: usage, total: totalTime)
                        DSDivider().padding(.leading, DS.Space.lg)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func recapSubtitle(_ recap: SessionRecap) -> String {
        let tf = DateFormatter(); tf.dateFormat = "h:mm a"
        let start = tf.string(from: recap.startedAt)
        let end   = tf.string(from: recap.endedAt)
        return "\(start) – \(end) · \(Int(recap.focusScore))% focus"
    }

    var scoreColor: Color {
        appTracker.focusScore >= 70 ? DS.C.green :
        appTracker.focusScore >= 40 ? DS.C.orange : DS.C.red
    }

    var statusText: String {
        if !appTracker.isTracking && appTracker.todayUsage.isEmpty { return "Not tracking" }
        if appTracker.focusScore >= 70 { return "Locked in 🔒" }
        if appTracker.focusScore >= 40 { return "Getting there" }
        return "Stay focused"
    }

    var productiveTime: TimeInterval {
        appTracker.todayUsage.filter { $0.category == .productive }.reduce(0) { $0 + $1.duration }
    }
    var distractingTime: TimeInterval {
        appTracker.todayUsage.filter { $0.category == .distracting }.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - Trends

struct TrendsSection: View {
    @EnvironmentObject var appTracker: AppTracker

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Trends")
                .font(DS.T.caption())
                .foregroundStyle(DS.C.textFaint)
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.md)

            HStack(spacing: DS.Space.sm) {
                TrendTile(label: "Focus score",
                          value: "\(Int(appTracker.avgFocusScore))",
                          unit: "%")
                TrendTile(label: "Focus/day",
                          value: formatDuration(appTracker.avgFocusedTimePerDay),
                          unit: nil)
                TrendTile(label: "Per session",
                          value: formatDuration(appTracker.avgSessionLength),
                          unit: nil)
            }
            .padding(.horizontal, DS.Space.lg)

            // 7-day sparkline
            Sparkline(records: appTracker.last7Days)
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.md)
        }
    }

    func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = Int(t) % 3600 / 60
        if h > 0 { return "\(h)h\(m)m" }
        if m > 0 { return "\(m)m" }
        return t > 0 ? "<1m" : "--"
    }
}

struct TrendTile: View {
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.C.textPrimary)
                if let unit {
                    Text(unit)
                        .font(DS.T.caption(10))
                        .foregroundStyle(DS.C.textFaint)
                }
            }
            Text(label)
                .font(DS.T.caption(10))
                .foregroundStyle(DS.C.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Space.sm)
        .padding(.horizontal, DS.Space.sm)
        .background(DS.C.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct Sparkline: View {
    let records: [DailyRecord]

    var maxScore: Double { max(records.map(\.focusScore).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let count = records.count
                let barW = (w - CGFloat(count - 1) * 3) / CGFloat(count)

                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(records) { rec in
                        let fraction = maxScore > 0 ? rec.focusScore / 100 : 0
                        let barH = max(CGFloat(fraction) * h, 2)
                        let color: Color = rec.focusScore >= 70 ? DS.C.green
                                        : rec.focusScore >= 40 ? DS.C.orange
                                        : rec.totalSeconds > 0 ? DS.C.red
                                        : DS.C.bg2
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(rec.totalSeconds > 0 ? 0.75 : 0.3))
                            .frame(width: barW, height: barH)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .frame(width: w)
            }
            .frame(height: 28)

            // Day labels (Mon, Tue…)
            HStack(spacing: 3) {
                ForEach(records) { rec in
                    Text(dayLabel(rec.dayKey))
                        .font(DS.T.caption(9))
                        .foregroundStyle(isToday(rec.dayKey) ? DS.C.accent : DS.C.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    func dayLabel(_ key: String) -> String {
        guard let date = AppTracker.dayFmtPublic.date(from: key) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return String(f.string(from: date).prefix(1))
    }

    func isToday(_ key: String) -> Bool {
        AppTracker.dayFmtPublic.string(from: Date()) == key
    }
}

// MARK: - Timeline

struct TimelineSection: View {
    let title: String
    let subtitle: String?
    let events: [AppEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.T.caption())
                    .foregroundStyle(DS.C.textFaint)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.T.caption(10))
                        .foregroundStyle(DS.C.textFaint.opacity(0.7))
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.sm)

            ForEach(events) { event in
                TimelineRow(event: event)
            }

            Spacer(minLength: DS.Space.sm)
        }
    }
}

struct TimelineRow: View {
    let event: AppEvent
    @State private var isHovered = false

    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: event.bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            // Time
            Text(timeLabel)
                .font(DS.T.mono(10))
                .foregroundStyle(DS.C.textFaint)
                .frame(width: 46, alignment: .trailing)

            // Category dot
            Circle()
                .fill(event.category.color.opacity(0.8))
                .frame(width: 5, height: 5)

            // Icon
            if let img = icon {
                Image(nsImage: img).resizable().frame(width: 14, height: 14)
            } else {
                RoundedRectangle(cornerRadius: 3).fill(DS.C.bg2).frame(width: 14, height: 14)
            }

            // Name
            Text(event.name)
                .font(DS.T.body())
                .foregroundStyle(DS.C.textPrimary)
                .lineLimit(1)

            Spacer()

            // Duration
            Text(formatDuration(event.duration))
                .font(DS.T.mono(11))
                .foregroundStyle(DS.C.textMuted)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, 5)
        .background(isHovered ? DS.C.bg1 : .clear)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    var timeLabel: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        return f.string(from: event.startTime)
    }

    func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = Int(t) % 3600 / 60; let s = Int(t) % 60
        if h > 0 { return "\(h)h\(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

// MARK: - Supporting views

struct StatPill: View {
    let label: String
    let time: TimeInterval
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(label) \(formatDuration(time))")
                .font(DS.T.caption())
                .foregroundStyle(DS.C.textMuted)
        }
    }

    func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = Int(t) % 3600 / 60
        if h > 0 { return "\(h)h\(m)m" }
        if m > 0 { return "\(m)m" }
        return t > 0 ? "<1m" : "--"
    }
}

struct AppRow: View {
    let usage: AppUsage
    let total: TimeInterval
    @State private var isHovered = false

    var fraction: Double { total > 0 ? min(usage.duration / total, 1) : 0 }

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Group {
                if let icon = usage.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.C.bg2)
                        .frame(width: 20, height: 20)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(usage.name)
                    .font(DS.T.body())
                    .foregroundStyle(DS.C.textPrimary)
                    .lineLimit(1)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(usage.category.color.opacity(0.15))
                        .frame(width: geo.size.width, height: 2)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(usage.category.color.opacity(0.6))
                                .frame(width: geo.size.width * fraction, height: 2)
                        }
                }
                .frame(height: 2)
            }

            Spacer()

            Text(formatDuration(usage.duration))
                .font(DS.T.mono(11))
                .foregroundStyle(DS.C.textMuted)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
        .background(isHovered ? DS.C.bg2 : .clear)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = Int(t) % 3600 / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
