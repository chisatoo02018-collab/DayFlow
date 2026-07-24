import SwiftUI
import WidgetKit
import AppIntents

struct WakeTimeComplicationEntry: TimelineEntry {
    let date: Date
    let wakeTime: Date
}

struct WakeTimeComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WakeTimeComplicationEntry {
        WakeTimeComplicationEntry(date: .now, wakeTime: Self.previewTime)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WakeTimeComplicationEntry) -> Void
    ) {
        completion(entry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WakeTimeComplicationEntry>) -> Void
    ) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> WakeTimeComplicationEntry {
        WakeTimeComplicationEntry(date: .now, wakeTime: WatchWakeTimeStore.time())
    }

    private static var previewTime: Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    }
}

struct WakeTimeComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WakeTimeComplicationEntry

    private var timeLabel: String {
        entry.wakeTime.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Button(intent: OpenWakeTimeEditorIntent()) {
            content
        }
            .buttonStyle(.plain)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "alarm.fill")
                        .font(.caption2)
                        .widgetAccentable()
                    Text(timeLabel)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
            }

        case .accessoryCorner:
            Image(systemName: "alarm.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel {
                    Text(timeLabel)
                        .monospacedDigit()
                }

        case .accessoryInline:
            ViewThatFits {
                Label("起床 \(timeLabel)", systemImage: "alarm.fill")
                Text(timeLabel)
                    .monospacedDigit()
            }

        default:
            HStack(spacing: 8) {
                Image(systemName: "alarm.fill")
                    .font(.title3)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("起床予定")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(timeLabel)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct WakeTimeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WatchWakeTimeStore.complicationKind,
            provider: WakeTimeComplicationProvider()
        ) { entry in
            WakeTimeComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("起床予定")
        .description("起床時刻を表示し、タップして変更できます。")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

@main
struct DayFlowWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WakeTimeComplication()
    }
}

#Preview(as: .accessoryRectangular) {
    WakeTimeComplication()
} timeline: {
    WakeTimeComplicationEntry(
        date: .now,
        wakeTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    )
}
