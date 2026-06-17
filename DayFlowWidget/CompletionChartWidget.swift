import SwiftUI
import WidgetKit
import EventKit

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
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)

        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay),
              let startOfWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let startOfMonth = cal.dateInterval(of: .month, for: now)?.start,
              let startOfYear = cal.dateInterval(of: .year, for: now)?.start
        else { return .placeholder }

        let day = fetchCompletion(from: startOfDay, to: endOfDay)
        let week = fetchCompletion(from: startOfWeek, to: endOfDay)
        let month = fetchCompletion(from: startOfMonth, to: endOfDay)
        let year = fetchCompletion(from: startOfYear, to: endOfDay)

        return CompletionChartEntry(date: now, day: day, week: week, month: month, year: year)
    }

    private func fetchCompletion(from start: Date, to end: Date) -> PeriodCompletion {
        let semaphore = DispatchSemaphore(value: 0)
        var completed = 0
        var incomplete = 0

        let completedPredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: start, ending: end, calendars: nil
        )
        store.fetchReminders(matching: completedPredicate) { fetched in
            completed = fetched?.count ?? 0
            semaphore.signal()
        }
        semaphore.wait()

        let incompletePredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: start, ending: end, calendars: nil
        )
        store.fetchReminders(matching: incompletePredicate) { fetched in
            incomplete = fetched?.count ?? 0
            semaphore.signal()
        }
        semaphore.wait()

        return PeriodCompletion(completed: completed, total: completed + incomplete)
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
        .description("Multi-ring donut showing completion rates by year, month, week, and day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Multi-ring donut view

struct RingData: Identifiable {
    let id: String
    let label: String
    let rate: Double
    let completed: Int
    let total: Int
    let color: Color
}

struct MultiRingDonutView: View {
    let rings: [RingData]
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let gap = lineWidth + 3

            ZStack {
                ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                    let radius = (size / 2) - CGFloat(index) * gap - lineWidth / 2

                    if radius > 0 {
                        Circle()
                            .stroke(ring.color.opacity(0.15), lineWidth: lineWidth)
                            .frame(width: radius * 2, height: radius * 2)
                            .position(center)

                        Circle()
                            .trim(from: 0, to: ring.rate)
                            .stroke(ring.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .frame(width: radius * 2, height: radius * 2)
                            .rotationEffect(.degrees(-90))
                            .position(center)
                    }
                }
            }
        }
    }
}

// MARK: - Widget views

struct CompletionChartWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CompletionChartEntry

    private var rings: [RingData] {
        [
            RingData(id: "year", label: "Year", rate: entry.year.rate,
                     completed: entry.year.completed, total: entry.year.total, color: .purple),
            RingData(id: "month", label: "Month", rate: entry.month.rate,
                     completed: entry.month.completed, total: entry.month.total, color: .blue),
            RingData(id: "week", label: "Week", rate: entry.week.rate,
                     completed: entry.week.completed, total: entry.week.total, color: .orange),
            RingData(id: "day", label: "Day", rate: entry.day.rate,
                     completed: entry.day.completed, total: entry.day.total, color: .green),
        ]
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    private var smallView: some View {
        VStack(spacing: 4) {
            Text("Completion")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            MultiRingDonutView(rings: rings, lineWidth: 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                ForEach(rings) { ring in
                    HStack(spacing: 2) {
                        Circle().fill(ring.color).frame(width: 4, height: 4)
                        Text("\(Int(ring.rate * 100))")
                            .font(.system(size: 9).weight(.semibold))
                    }
                }
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            MultiRingDonutView(rings: rings, lineWidth: 9)
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 6) {
                Text("Completion Rate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(rings) { ring in
                    ringLegendRow(ring: ring)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var largeView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Completion Rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Date(), format: .dateTime.month(.wide).day().year())
                        .font(.headline.weight(.bold))
                }
                Spacer()
            }

            MultiRingDonutView(rings: rings, lineWidth: 14)
                .frame(height: 170)

            VStack(spacing: 8) {
                ForEach(rings) { ring in
                    ringDetailRow(ring: ring)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func ringLegendRow(ring: RingData) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(ring.color)
                .frame(width: 10, height: 10)
            Text(ring.label)
                .font(.caption)
            Spacer()
            Text("\(Int(ring.rate * 100))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(ring.color)
        }
    }

    private func ringDetailRow(ring: RingData) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(ring.color)
                .frame(width: 12, height: 12)
            Text(ring.label)
                .font(.subheadline)
            Spacer()
            Text("\(ring.completed)/\(ring.total)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(ring.rate * 100))%")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ring.color)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
