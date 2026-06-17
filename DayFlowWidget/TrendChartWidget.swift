import SwiftUI
import WidgetKit
import EventKit
import Charts

struct TrendChartProvider: AppIntentTimelineProvider {
    private let store = EKEventStore()

    func placeholder(in context: Context) -> TrendChartEntry {
        .placeholder
    }

    func snapshot(for configuration: TrendChartIntent, in context: Context) async -> TrendChartEntry {
        fetchEntry(configuration: configuration)
    }

    func timeline(for configuration: TrendChartIntent, in context: Context) async -> Timeline<TrendChartEntry> {
        let entry = fetchEntry(configuration: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func fetchEntry(configuration: TrendChartIntent) -> TrendChartEntry {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = configuration.period.rawValue

        var stats: [DailyStats] = []
        for offset in (0..<days).reversed() {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let eventPredicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
            let eventCount = store.events(matching: eventPredicate).count

            var completedCount = 0
            var totalCount = 0
            let semaphore = DispatchSemaphore(value: 0)

            let completedPredicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: dayStart, ending: dayEnd, calendars: nil
            )
            store.fetchReminders(matching: completedPredicate) { fetched in
                completedCount = fetched?.count ?? 0
                semaphore.signal()
            }
            semaphore.wait()

            let incompletePredicate = store.predicateForIncompleteReminders(
                withDueDateStarting: dayStart, ending: dayEnd, calendars: nil
            )
            store.fetchReminders(matching: incompletePredicate) { fetched in
                totalCount = completedCount + (fetched?.count ?? 0)
                semaphore.signal()
            }
            semaphore.wait()

            stats.append(DailyStats(
                id: dayStart, date: dayStart,
                eventCount: eventCount,
                completedCount: completedCount,
                totalReminderCount: totalCount
            ))
        }

        let showEvents = configuration.displayContent != .completionsOnly
        let showCompletions = configuration.displayContent != .eventsOnly

        return TrendChartEntry(
            date: Date(), dailyStats: stats,
            showEvents: showEvents, showCompletions: showCompletions,
            showCompletionRate: configuration.showCompletionRate
        )
    }
}

struct TrendChartWidget: Widget {
    let kind = "TrendChartWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TrendChartIntent.self, provider: TrendChartProvider()) { entry in
            TrendChartWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Activity Trend")
        .description("Track your events and task completion trends.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TrendChartWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TrendChartEntry

    private var periodLabel: String {
        "\(entry.dailyStats.count)-Day Trend"
    }

    var body: some View {
        switch family {
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(periodLabel, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                chartLegend
            }

            activityChart
                .frame(maxHeight: .infinity)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Overview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(periodLabel)
                        .font(.headline.weight(.bold))
                }
                Spacer()
                chartLegend
            }

            Text("Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            activityChart
                .frame(height: 120)

            if entry.showCompletionRate {
                Divider()

                Text("Completion Rate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                completionRateChart
                    .frame(height: 100)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var chartLegend: some View {
        HStack(spacing: 8) {
            if entry.showEvents {
                legendDot(color: .blue, label: "Events")
            }
            if entry.showCompletions {
                legendDot(color: .green, label: "Done")
            }
        }
    }

    private var activityChart: some View {
        Chart(entry.dailyStats) { stat in
            if entry.showEvents {
                LineMark(
                    x: .value("Day", stat.date, unit: .day),
                    y: .value("Events", stat.eventCount)
                )
                .foregroundStyle(.blue)
                .symbol(Circle())
                .interpolationMethod(.catmullRom)
            }

            if entry.showCompletions {
                LineMark(
                    x: .value("Day", stat.date, unit: .day),
                    y: .value("Completed", stat.completedCount)
                )
                .foregroundStyle(.green)
                .symbol(Diamond())
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }

    private var completionRateChart: some View {
        Chart(entry.dailyStats) { stat in
            BarMark(
                x: .value("Day", stat.date, unit: .day),
                y: .value("Rate", stat.completionRate * 100)
            )
            .foregroundStyle(
                stat.completionRate >= 0.8 ? .green :
                stat.completionRate >= 0.5 ? .orange : .red
            )
            .cornerRadius(3)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%").font(.caption2)
                    }
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct Diamond: ChartSymbolShape {
    var perceptualUnitRect: CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
        }
    }
}
