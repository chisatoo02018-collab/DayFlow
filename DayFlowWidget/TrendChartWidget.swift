import SwiftUI
import WidgetKit
import EventKit
import Charts

struct TrendChartProvider: TimelineProvider {
    private let store = EKEventStore()

    func placeholder(in context: Context) -> TrendChartEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TrendChartEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendChartEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchEntry() -> TrendChartEntry {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var stats: [DailyStats] = []
        for offset in (0..<7).reversed() {
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

        return TrendChartEntry(date: Date(), dailyStats: stats)
    }
}

struct TrendChartWidget: Widget {
    let kind = "TrendChartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrendChartProvider()) { entry in
            TrendChartWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weekly Trend")
        .description("Track your events and task completion over the past 7 days.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TrendChartWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TrendChartEntry

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
                Label("7-Day Trend", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                HStack(spacing: 8) {
                    legendDot(color: .blue, label: "Events")
                    legendDot(color: .green, label: "Done")
                }
            }

            eventAndCompletionChart
                .frame(maxHeight: .infinity)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Weekly Overview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("7-Day Trend")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                HStack(spacing: 8) {
                    legendDot(color: .blue, label: "Events")
                    legendDot(color: .green, label: "Done")
                }
            }

            Text("Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            eventAndCompletionChart
                .frame(height: 120)

            Divider()

            Text("Completion Rate")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            completionRateChart
                .frame(height: 100)

            Spacer(minLength: 0)
        }
    }

    private var eventAndCompletionChart: some View {
        Chart(entry.dailyStats) { stat in
            LineMark(
                x: .value("Day", stat.date, unit: .day),
                y: .value("Events", stat.eventCount)
            )
            .foregroundStyle(.blue)
            .symbol(Circle())
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Day", stat.date, unit: .day),
                y: .value("Completed", stat.completedCount)
            )
            .foregroundStyle(.green)
            .symbol(Diamond())
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
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
            AxisMarks(values: .stride(by: .day)) { value in
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
