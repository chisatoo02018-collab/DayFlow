import SwiftUI
import WidgetKit
import EventKit
import Charts

struct CompletionChartProvider: TimelineProvider {
    private let store = EKEventStore()

    func placeholder(in context: Context) -> CompletionChartEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CompletionChartEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompletionChartEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchEntry() -> CompletionChartEntry {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            return .placeholder
        }

        var completedCount = 0
        var remainingCount = 0
        var overdueCount = 0

        let semaphore = DispatchSemaphore(value: 0)

        let completedPredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: startOfDay, ending: endOfDay, calendars: nil
        )
        store.fetchReminders(matching: completedPredicate) { fetched in
            completedCount = fetched?.count ?? 0
            semaphore.signal()
        }
        semaphore.wait()

        let incompletePredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: endOfDay, calendars: nil
        )
        store.fetchReminders(matching: incompletePredicate) { fetched in
            if let fetched {
                remainingCount = fetched.count
                overdueCount = fetched.filter {
                    guard let due = $0.dueDateComponents?.date else { return false }
                    return due < Date()
                }.count
            }
            semaphore.signal()
        }
        semaphore.wait()

        return CompletionChartEntry(
            date: Date(),
            completedCount: completedCount,
            remainingCount: remainingCount,
            overdueCount: overdueCount
        )
    }
}

struct CompletionChartWidget: Widget {
    let kind = "CompletionChartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompletionChartProvider()) { entry in
            CompletionChartWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Completion Rate")
        .description("Visualize your reminder completion rate with a donut chart.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CompletionChartWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CompletionChartEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    private var smallView: some View {
        VStack(spacing: 6) {
            Text("Completion")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            donutChart
                .frame(height: 90)

            Text("\(Int(entry.completionRate * 100))%")
                .font(.title3.weight(.bold))
                .foregroundStyle(.green)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Today's Progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                donutChart
                    .frame(width: 100, height: 100)
            }

            VStack(alignment: .leading, spacing: 10) {
                legendItem(color: .green, label: "Completed", value: entry.completedCount)
                legendItem(color: .blue.opacity(0.4), label: "Remaining", value: entry.remainingCount)
                if entry.overdueCount > 0 {
                    legendItem(color: .red, label: "Overdue", value: entry.overdueCount)
                }

                Spacer()

                Text("\(Int(entry.completionRate * 100))% done")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var donutChart: some View {
        Chart {
            if entry.total == 0 {
                SectorMark(angle: .value("Empty", 1), innerRadius: .ratio(0.6))
                    .foregroundStyle(.gray.opacity(0.2))
            } else {
                SectorMark(
                    angle: .value("Completed", entry.completedCount),
                    innerRadius: .ratio(0.6)
                )
                .foregroundStyle(.green)

                if entry.overdueCount > 0 {
                    SectorMark(
                        angle: .value("Overdue", entry.overdueCount),
                        innerRadius: .ratio(0.6)
                    )
                    .foregroundStyle(.red)
                }

                let nonOverdueRemaining = max(0, entry.remainingCount - entry.overdueCount)
                if nonOverdueRemaining > 0 {
                    SectorMark(
                        angle: .value("Remaining", nonOverdueRemaining),
                        innerRadius: .ratio(0.6)
                    )
                    .foregroundStyle(.blue.opacity(0.3))
                }
            }
        }
        .chartLegend(.hidden)
    }

    private func legendItem(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)").font(.caption.weight(.semibold))
        }
    }
}
