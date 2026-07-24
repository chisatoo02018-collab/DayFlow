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
            daysWithData: 14, officeDays: 9,
            timeline: Array(repeating: "sleep", count: 84) + Array(repeating: "work", count: 96) + Array(repeating: "leisure", count: 108)), openDestination: .insights)
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
                HStack(alignment: .top, spacing: 12) {
                    TypicalDayRing(timeline: entry.typical.timeline, averages: entry.typical.averages)
                        .frame(width: family == .systemSmall ? 74 : 92, height: family == .systemSmall ? 74 : 92)
                    VStack(spacing: 5) {
                        ForEach(entry.typical.averages.prefix(topN)) { avg in row(avg) }
                    }
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

private struct TypicalDayRing: View {
    let timeline: [String?]
    let averages: [DayFlowSharedStore.CategoryAverage]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 7
            let colors = Dictionary(uniqueKeysWithValues: averages.map { ($0.id, Color(hex: $0.colorHex)) })
            for block in runs {
                var path = Path()
                path.addArc(center: center, radius: radius,
                            startAngle: .degrees(Double(block.start) / 1440 * 360 - 90),
                            endAngle: .degrees(Double(block.end) / 1440 * 360 - 90), clockwise: false)
                context.stroke(path, with: .color(colors[block.categoryID] ?? .gray), style: StrokeStyle(lineWidth: 12))
            }
            let text = context.resolve(Text("平均").font(.caption2.weight(.bold)).foregroundColor(.secondary))
            context.draw(text, at: center)
        }
        .accessibilityLabel("平均的な1日の時間リング")
    }

    private var runs: [(categoryID: String, start: Int, end: Int)] {
        var result: [(String, Int, Int)] = []
        var index = 0
        while index < timeline.count {
            guard let category = timeline[index] else { index += 1; continue }
            var end = index + 1
            while end < timeline.count, timeline[end] == category { end += 1 }
            result.append((category, index * 5, end * 5))
            index = end
        }
        return result
    }
}

struct TypicalDayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TypicalDayWidget", intent: TypicalDayWidgetIntent.self, provider: TypicalDayProvider()) { entry in
            TypicalDayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DayFlowSharedStore.deepLink(for: .todayActual))
        }
        .configurationDisplayName("よく過ごす1日")
        .description("記録した実績を平均して、平均的な1日の過ごし方を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
