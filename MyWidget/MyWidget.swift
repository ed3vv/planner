import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
    let relevance: TimelineEntryRelevance?

    init(date: Date, relevance: TimelineEntryRelevance? = nil) {
        self.date = date
        self.relevance = relevance
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        var entries: [SimpleEntry] = []
        let currentDate = Date()

        // Generate a timeline with one entry per minute for the next hour.
        for minuteOffset in 0 ..< 60 {
            let entryDate = Calendar.current.date(
                byAdding: .minute,
                value: minuteOffset,
                to: currentDate
            )!
            let entry = SimpleEntry(date: entryDate)
            entries.append(entry)
        }

        // Refresh the timeline after the last entry elapses.
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

// MARK: - Widget Views

struct MyWidgetSmallView: View {
    let entry: SimpleEntry

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.date)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
                Spacer()
            }

            Spacer()

            Text(timeString)
                .font(.title2)
                .fontWeight(.semibold)
                .minimumScaleFactor(0.7)

            Text(dateString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MyWidgetMediumView: View {
    let entry: SimpleEntry

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: entry.date)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: entry.date)
    }

    private var weekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left column: icon and time
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.title)
                    .foregroundStyle(.blue)

                Text(timeString)
                    .font(.title2)
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Right column: date info
            VStack(alignment: .leading, spacing: 4) {
                Text(weekday)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(dateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                Text("Updated \(entry.date, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Entry View (dispatches to size-specific views)

struct MyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: SimpleEntry

    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            MyWidgetSmallView(entry: entry)
        case .systemMedium:
            MyWidgetMediumView(entry: entry)
        default:
            MyWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    MyWidget()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview("Medium", as: .systemMedium) {
    MyWidget()
} timeline: {
    SimpleEntry(date: .now)
}
