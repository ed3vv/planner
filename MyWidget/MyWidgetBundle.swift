import WidgetKit
import SwiftUI

// MARK: - Widget Definition

struct MyWidget: Widget {
    /// A stable, unique string that WidgetKit uses to identify the widget.
    let kind: String = "MyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("My Widget")
        .description("Shows the current time and date.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // Limit the number of widgets a user can add (optional).
        // .contentMarginsDisabled() // Uncomment to take full control of padding on macOS 14+
    }
}

// MARK: - Widget Bundle

/// The bundle is the top-level entry point for the widget extension.
/// List every Widget type you want to expose here.
@main
struct MyWidgetBundle: WidgetBundle {
    var body: some Widget {
        MyWidget()
    }
}
