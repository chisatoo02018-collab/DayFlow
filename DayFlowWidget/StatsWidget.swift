import SwiftUI
import WidgetKit
import Charts

struct StatsProvider: AppIntentTimelineProvider {
    private let data = WidgetDataProvider()

    func placeholder(in context: Context) -> StatsEntry { .placeholder }

    func snapshot(for configuration: StatsWidgetIntent, in context: Context) async -> StatsEntry {
        fetchEntry(configuration)
    }

    func timeline(for configuration: StatsWidgetIntent, in context: Context) async -> Timeline<StatsEntry> {
        let entry = fetchEntry(configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func fetchEntry(_ config: StatsWidgetIntent) -> StatsEntry {
        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)

        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay),
              let startOfWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let startOfMonth = cal.dateInterval(of: .month, for: now)?.start,
              let startOfYear = cal.dateInterval(of: .year, for: now)?.start
        else { return .placeholder }

        return StatsEntry(
            date: now,
            day: data.fetchCompletion(from: startOfDay, to: endOfDay),
            week: data.fetchCompletion(from: startOfWeek, to: endOfDay),
            month: data.fetchCompletion(from: startOfMonth, to: endOfDay),
            year: data.fetchCompletion(from: startOfYear, to: endOfDay),
            trend: data.fetchDailyTrend(days: config.trendDays.rawValue)
        )
    }
}

struct StatsWidget: Widget {
    let kind = "CompletionChartWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StatsWidgetIntent.self, provider: StatsProvider()) { entry in
            StatsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("DayFlow Stats")
        .description("Completion rates and activity trends.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Ring component

struct RingData: Identifiable {
    let id: String
    let label: String
    let completion: PeriodCompletion
    let color: Color
}

struct MultiRingView: View {
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
                            .stroke(ring.completion.hasData ? ring.color.opacity(0.15) : .gray.opacity(0.1),
                                    lineWidth: lineWidth)
                            .frame(width: radius * 2, height: radius * 2)
                            .position(center)

                        if let rate = ring.completion.rate {
                            Circle()
                                .trim(from: 0, to: rate)
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
}

// MARK: - Views

struct StatsWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: StatsEntry

    private var rings: [RingData] {
        [
            RingData(id: "year", label: "Year", completion: entry.year, color: .purple),
            RingData(id: "month", label: "Month", completion: entry.month, color: .blue),
            RingData(id: "week", label: "Week", completion: entry.week, color: .orange),
            RingData(id: "day", label: "Day", completion: entry.day, color: .green),
        ]
    }

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemLarge: largeView
        default: mediumView
        }
    }

    private var smallView: some View {
        VStack(spacing: 4) {
            Text("Completion").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)

            MultiRingView(rings: rings, lineWidth: 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                ForEach(rings) { ring in
                    HStack(spacing: 2) {
                        Circle().fill(ring.completion.hasData ? ring.color : .gray.opacity(0.3))
                            .frame(width: 4, height: 4)
                        Text(ring.completion.rate.map { "\(Int($0 * 100))" } ?? "—")
                            .font(.system(size: 9).weight(.semibold))
                            .foregroundStyle(ring.completion.hasData ? .primary : .secondary)
                    }
                }
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            MultiRingView(rings: rings, lineWidth: 9)
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 5) {
                Text("Completion").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                ForEach(rings) { ring in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(ring.color).frame(width: 10, height: 10)
                        Text(ring.label).font(.caption)
                        Spacer()
                        if let rate = ring.completion.rate {
                            Text("\(Int(rate * 100))%").font(.caption.weight(.bold)).foregroundStyle(ring.color)
                        } else {
                            Text("—").font(.caption).foregroundStyle(.gray.opacity(0.4))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var largeView: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Stats").font(.caption).foregroundStyle(.secondary)
                    Text(Date(), format: .dateTime.month(.wide).day().year()).font(.headline.weight(.bold))
                }
                Spacer()
            }

            HStack(spacing: 16) {
                MultiRingView(rings: rings, lineWidth: 10)
                    .frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rings) { ring in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(ring.color).frame(width: 10, height: 10)
                            Text(ring.label).font(.caption)
                            Spacer()
                            if ring.completion.hasData {
                                Text("\(ring.completion.completed)/\(ring.completion.total)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if let rate = ring.completion.rate {
                                Text("\(Int(rate * 100))%").font(.caption.weight(.bold)).foregroundStyle(ring.color)
                                    .frame(width: 38, alignment: .trailing)
                            } else {
                                Text("—").font(.caption).foregroundStyle(.gray.opacity(0.4))
                                    .frame(width: 38, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            Divider()

            Text("\(entry.trend.count)-Day Trend").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            trendChart.frame(maxHeight: .infinity)

            Spacer(minLength: 0)
        }
    }

    private var trendChart: some View {
        Chart(entry.trend) { stat in
            BarMark(
                x: .value("Day", stat.date, unit: .day),
                y: .value("Count", stat.eventCount + stat.completedCount)
            )
            .foregroundStyle(
                stat.completionRate.map { rate in
                    rate >= 0.8 ? Color.green : rate >= 0.5 ? .orange : .red
                } ?? .gray.opacity(0.3)
            )
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, entry.trend.count / 7))) { _ in
                AxisValueLabel(format: .dateTime.day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }
}
