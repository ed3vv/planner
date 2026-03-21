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

// MARK: - StatsView

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

                // Trends + Stats on same page
                TrendsSection()
                    .environmentObject(appTracker)

                DSDivider()

                // Last session recap
                if let recap = appTracker.lastRecap {
                    SessionTimelineSection(
                        title: "Last session",
                        subtitle: recapSubtitle(recap),
                        events: recap.events,
                        start: recap.startedAt,
                        end: recap.endedAt
                    )
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
                        AppRow(usage: usage, total: totalTime) { newCat in
                            if let newCat { appTracker.setCategory(newCat, for: usage.bundleID) }
                            else          { appTracker.resetCategory(for: usage.bundleID) }
                        }
                        DSDivider().padding(.leading, DS.Space.lg)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func recapSubtitle(_ recap: SessionRecap) -> String {
        let tf = DateFormatter(); tf.dateFormat = "h:mm a"
        return "\(tf.string(from: recap.startedAt)) – \(tf.string(from: recap.endedAt))  ·  \(Int(recap.focusScore))% focus"
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

// MARK: - Session timeline section (header + bar)

struct SessionTimelineSection: View {
    let title: String
    let subtitle: String?
    let events: [AppEvent]
    let start: Date
    let end: Date

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

            TimelineBar(events: events, startTime: start, endTime: end)
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.md)
        }
    }
}

// MARK: - Wakatime-style timeline bar

struct TimelineBar: View {
    let events: [AppEvent]
    let startTime: Date
    let endTime: Date

    @State private var hoveredEvent: AppEvent? = nil

    var totalDuration: TimeInterval { max(endTime.timeIntervalSince(startTime), 1) }
    var midTime: Date { startTime.addingTimeInterval(totalDuration / 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.C.bg2)
                        .frame(height: 22)

                    // Segments
                    ForEach(events) { event in
                        segment(event: event, width: geo.size.width)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let pt):
                        let frac = Double(pt.x / max(geo.size.width, 1))
                        let t    = startTime.addingTimeInterval(totalDuration * max(0, min(1, frac)))
                        hoveredEvent = events.last(where: { $0.startTime <= t })
                    case .ended:
                        hoveredEvent = nil
                    }
                }
            }
            .frame(height: 22)

            // Tooltip row / time axis
            HStack(spacing: DS.Space.xs) {
                if let e = hoveredEvent {
                    Circle()
                        .fill(e.category.color)
                        .frame(width: 5, height: 5)
                    Text(e.name)
                        .font(DS.T.caption(11))
                        .foregroundStyle(DS.C.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(fmtDuration(e.duration))
                        .font(DS.T.mono(10))
                        .foregroundStyle(DS.C.textFaint)
                } else {
                    Text(fmtTime(startTime))
                        .font(DS.T.mono(9))
                        .foregroundStyle(DS.C.textFaint)
                    Spacer()
                    Text(fmtTime(midTime))
                        .font(DS.T.mono(9))
                        .foregroundStyle(DS.C.textFaint)
                    Spacer()
                    Text(fmtTime(endTime))
                        .font(DS.T.mono(9))
                        .foregroundStyle(DS.C.textFaint)
                }
            }
            .animation(.easeOut(duration: 0.1), value: hoveredEvent?.id)
            .frame(height: 14)
        }
    }

    @ViewBuilder
    private func segment(event: AppEvent, width: CGFloat) -> some View {
        let offset = CGFloat(event.startTime.timeIntervalSince(startTime) / totalDuration) * width
        let segW   = max(CGFloat(event.duration / totalDuration) * width, 1.5)
        let isHov  = hoveredEvent?.id == event.id

        Rectangle()
            .fill(event.category.color.opacity(isHov ? 0.95 : 0.6))
            .frame(width: segW, height: 22)
            .offset(x: offset)
    }

    private func fmtTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f.string(from: date)
    }
    private func fmtDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = Int(t) % 3600 / 60; let s = Int(t) % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
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
                TrendTile(label: "Avg focus",     value: "\(Int(appTracker.avgFocusScore))", unit: "%")
                TrendTile(label: "Focus/day",     value: fmtDuration(appTracker.avgFocusedTimePerDay), unit: nil)
                TrendTile(label: "Per session",   value: fmtDuration(appTracker.avgSessionLength),     unit: nil)
            }
            .padding(.horizontal, DS.Space.lg)

            // 7-day sparkline
            Sparkline(records: appTracker.last7Days)
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.md)
        }
    }

    func fmtDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = Int(t) % 3600 / 60
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
    @State private var hoveredRecord: DailyRecord? = nil

    var maxScore: Double { max(records.map(\.focusScore).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Tooltip row
            HStack(spacing: DS.Space.xs) {
                if let r = hoveredRecord {
                    Text(hoveredDayLabel(r.dayKey))
                        .font(DS.T.mono(10))
                        .foregroundStyle(DS.C.textFaint)
                    Spacer()
                    HStack(spacing: DS.Space.sm) {
                        HStack(spacing: 3) {
                            Circle().fill(DS.C.green).frame(width: 5, height: 5)
                            Text(fmtDuration(r.productiveSeconds))
                                .font(DS.T.mono(10))
                                .foregroundStyle(DS.C.textPrimary)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(DS.C.red).frame(width: 5, height: 5)
                            Text(fmtDuration(r.distractingSeconds))
                                .font(DS.T.mono(10))
                                .foregroundStyle(DS.C.textPrimary)
                        }
                        Text("\(Int(r.focusScore))%")
                            .font(DS.T.mono(10))
                            .foregroundStyle(DS.C.textFaint)
                    }
                }
            }
            .frame(height: 14)
            .animation(.easeOut(duration: 0.1), value: hoveredRecord?.dayKey)

            GeometryReader { geo in
                let w     = geo.size.width
                let h     = geo.size.height
                let count = records.count
                let barW  = (w - CGFloat(count - 1) * 3) / CGFloat(count)

                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(records) { rec in
                        let fraction = maxScore > 0 ? rec.focusScore / 100 : 0
                        let barH     = max(CGFloat(fraction) * h, 2)
                        let isHov    = hoveredRecord?.dayKey == rec.dayKey
                        let color: Color = rec.focusScore >= 70 ? DS.C.green
                                        : rec.focusScore >= 40 ? DS.C.orange
                                        : rec.totalSeconds > 0 ? DS.C.red
                                        : DS.C.bg2
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(isHov ? 1.0 : (rec.totalSeconds > 0 ? 0.75 : 0.3)))
                            .frame(width: barW, height: isHov ? min(barH + 2, h) : barH)
                            .onHover { inside in hoveredRecord = inside ? rec : nil }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .frame(width: w)
            }
            .frame(height: 28)

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
        let f = DateFormatter(); f.dateFormat = "EEE"
        return String(f.string(from: date).prefix(1))
    }
    func hoveredDayLabel(_ key: String) -> String {
        guard let date = AppTracker.dayFmtPublic.date(from: key) else { return key }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
    func isToday(_ key: String) -> Bool { AppTracker.dayFmtPublic.string(from: Date()) == key }
    func fmtDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = Int(t) % 3600 / 60
        if h > 0 { return "\(h)h\(m)m" }
        if m > 0 { return "\(m)m" }
        return t > 0 ? "<1m" : "--"
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
            Text("\(label) \(fmtDuration(time))")
                .font(DS.T.caption())
                .foregroundStyle(DS.C.textMuted)
        }
    }

    func fmtDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = Int(t) % 3600 / 60
        if h > 0 { return "\(h)h\(m)m" }
        if m > 0 { return "\(m)m" }
        return t > 0 ? "<1m" : "--"
    }
}

struct AppRow: View {
    let usage: AppUsage
    let total: TimeInterval
    var onSetCategory: ((AppCategory?) -> Void)? = nil   // nil = reset to default
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

            Text(fmtDuration(usage.duration))
                .font(DS.T.mono(11))
                .foregroundStyle(DS.C.textMuted)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
        .background(isHovered ? DS.C.bg2 : .clear)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .contextMenu {
            if let setter = onSetCategory {
                Text(usage.name).font(.headline)
                Divider()
                Button {
                    setter(.productive)
                } label: {
                    Label("Productive", systemImage: usage.category == .productive ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    setter(.neutral)
                } label: {
                    Label("Neutral", systemImage: usage.category == .neutral ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    setter(.distracting)
                } label: {
                    Label("Distracting", systemImage: usage.category == .distracting ? "checkmark.circle.fill" : "circle")
                }
                Divider()
                Button("Reset to default") { setter(nil) }
            }
        }
    }

    func fmtDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = Int(t) % 3600 / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
