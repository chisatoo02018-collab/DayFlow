import SwiftUI
import WidgetKit

/// "どんな1日をよく過ごしているか" — averages the recorded 実績 into a typical-day
/// breakdown: a stacked 24h bar plus the top categories with their average time.
struct TypicalDayEntry: TimelineEntry {
    let date: Date
    let typical: DayFlowSharedStore.TypicalDay
    let openDestination: WidgetOpenDestination

    static var placeholder: TypicalDayEntry {
        TypicalDayEntry(date: Date(), typical: .init(
            averages: [
                .init(id: "sleep", name: "睡眠", colorHex: "#4C6EF5", averageMinutes: 420),
                .init(id: "work", name: "仕事", colorHex: "#FA5252", averageMinutes: 480),
                .init(id: "meal", name: "食事", colorHex: "#FD7E14", averageMinutes: 90),
                .init(id: "leisure", name: "娯楽", colorHex: "#F783AC", averageMinutes: 150),
                .init(id: "commute", name: "移動", colorHex: "#22B8CF", averageMinutes: 60),
            ],
            daysWithData: 14, officeDays: 9), openDestination: .insights)
    }
}

struct TypicalDayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TypicalDayEntry { .placeholder }

    func snapshot(for configuration: TypicalDayWidgetIntent, in context: Context) async -> TypicalDayEntry {
        context.isPreview ? .placeholder : entry(configuration)
    }

    func timeline(for configuration: TypicalDayWidgetIntent, in context: Context) async -> Timeline<TypicalDayEntry> {
        let entry = entry(configuration)
        // Recorded days change at most once a day; refresh a few times to stay current.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(_ configuration: TypicalDayWidgetIntent) -> TypicalDayEntry {
        TypicalDayEntry(date: Date(), typical: DayFlowSharedStore.typicalDay(),
                        openDestination: configuration.openDestination)
    }
}

struct TypicalDayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TypicalDayEntry

    private var topN: Int { family == .systemLarge ? 6 : (family == .systemMedium ? 4 : 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("よく過ごす1日")
                    .font(.caption.weight(.semibold))
                Spacer()
                if entry.typical.daysWithData > 0 {
                    Text("直近\(entry.typical.daysWithData)日")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if entry.typical.averages.isEmpty {
                Spacer()
                Text("実績を記録すると、平均的な1日が見えてきます")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                stackedBar
                ForEach(entry.typical.averages.prefix(topN)) { avg in
                    row(avg)
                }
                if entry.typical.officeDays > 0 {
                    Text("出社 \(entry.typical.officeDays)/\(entry.typical.daysWithData)日")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    /// A single 24h bar, each category a slice proportional to its average minutes.
    private var stackedBar: some View {
        GeometryReader { geo in
            let total = max(1, entry.typical.averages.reduce(0) { $0 + $1.averageMinutes })
            HStack(spacing: 1) {
                ForEach(entry.typical.averages) { avg in
                    Color(hex: avg.colorHex)
                        .frame(width: geo.size.width * CGFloat(avg.averageMinutes) / CGFloat(total))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    private func row(_ avg: DayFlowSharedStore.CategoryAverage) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: avg.colorHex)).frame(width: 8, height: 8)
            Text(avg.name).font(.caption2)
            Spacer()
            Text(hoursMinutes(avg.averageMinutes))
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func hoursMinutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h\(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

struct TypicalDayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TypicalDayWidget", intent: TypicalDayWidgetIntent.self, provider: TypicalDayProvider()) { entry in
            TypicalDayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DayFlowSharedStore.deepLink(for: entry.openDestination.route))
        }
        .configurationDisplayName("よく過ごす1日")
        .description("記録した実績を平均して、平均的な1日の過ごし方を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
