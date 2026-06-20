import SwiftUI

struct MonthSummary: Identifiable {
    let id: Date
    let date: Date
    let eventCount: Int
    let completedCount: Int
    let incompleteCount: Int
    var total: Int { completedCount + incompleteCount }
    var hasReminderData: Bool { total > 0 }
    var completionRate: Double? {
        guard total > 0 else { return nil }
        return Double(completedCount) / Double(total)
    }
}

struct YearStats {
    var totalEvents: Int = 0
    var totalCompleted: Int = 0
    var totalIncomplete: Int = 0
    var monthsWithData: Int = 0
    var busiestMonth: Date?
    var busiestMonthCount: Int = 0
    var bestMonth: Date?
    var bestRate: Double = 0

    var completionRate: Double? {
        let total = totalCompleted + totalIncomplete
        guard total > 0 else { return nil }
        return Double(totalCompleted) / Double(total)
    }
}

struct YearView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(ReminderService.self) private var reminderService
    @State private var displayedYear = Date()
    @State private var monthSummaries: [MonthSummary] = []
    @State private var stats = YearStats()
    @State private var loading = false
    @State private var showNewItem = false

    private let calendar = Calendar.current
    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    yearNavigator
                    yearGrid
                    yearStatsSection
                    yearBarChart
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewItem = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewItem) {
                NewItemSheet { await loadYear() }
            }
            .task(id: displayedYear) { await loadYear() }
        }
    }

    private var yearNavigator: some View {
        HStack {
            Button { shiftYear(-1) } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            Spacer()
            Text(displayedYear, format: .dateTime.year())
                .font(.title3.weight(.bold))
            Spacer()
            Button { shiftYear(1) } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.semibold))
            }
        }
        .padding(.horizontal, 4)
    }

    private var yearGrid: some View {
        LazyVGrid(columns: monthColumns, spacing: 6) {
            ForEach(monthSummaries) { month in
                monthCard(month)
            }
        }
        .overlay { if loading { ProgressView() } }
    }

    private func monthCard(_ month: MonthSummary) -> some View {
        let isCurrentMonth = calendar.isDate(month.date, equalTo: Date(), toGranularity: .month)

        return HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.gray.opacity(0.15), lineWidth: 3)
                if let rate = month.completionRate {
                    Circle()
                        .trim(from: 0, to: rate)
                        .stroke(rateColor(rate), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(month.date, format: .dateTime.month(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isCurrentMonth ? .blue : .primary)
                HStack(spacing: 4) {
                    if let rate = month.completionRate {
                        Text("\(Int(rate * 100))%")
                            .foregroundStyle(rateColor(rate))
                    } else {
                        Text("—")
                            .foregroundStyle(.gray.opacity(0.4))
                    }
                    Text("·")
                    Text("\(month.eventCount)ev")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .overlay {
            if isCurrentMonth {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue.opacity(0.3), lineWidth: 1.5)
            }
        }
    }

    private var yearStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yearly Summary")
                .font(.headline)

            HStack(spacing: 12) {
                miniStat(title: "Events", value: "\(stats.totalEvents)", icon: "calendar", color: .blue)
                miniStat(title: "Completed", value: "\(stats.totalCompleted)", icon: "checkmark.circle", color: .green)
                miniStat(title: "Remaining", value: "\(stats.totalIncomplete)", icon: "circle", color: .orange)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completion Rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let rate = stats.completionRate {
                        Text("\(Int(rate * 100))%")
                            .font(.title.weight(.bold))
                            .foregroundStyle(rateColor(rate))
                    } else {
                        Text("—")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.gray.opacity(0.4))
                    }
                }

                Spacer()

                if let best = stats.bestMonth {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Best Month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(best, format: .dateTime.month(.wide))
                            .font(.title3.weight(.bold))
                        Text("\(Int(stats.bestRate * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var yearBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly Activity")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(monthSummaries) { month in
                    VStack(spacing: 4) {
                        let maxVal = max(1, monthSummaries.map { $0.eventCount + $0.completedCount }.max() ?? 1)
                        let height = CGFloat(month.eventCount + month.completedCount) / CGFloat(maxVal) * 100

                        RoundedRectangle(cornerRadius: 3)
                            .fill(month.completionRate.map { rateColor($0) } ?? .gray.opacity(0.3))
                            .frame(height: max(4, height))

                        Text(month.date, format: .dateTime.month(.narrow))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)

            HStack(spacing: 12) {
                legendDot(color: .green, label: "≥80%")
                legendDot(color: .orange, label: "50-79%")
                legendDot(color: .red, label: "<50%")
                legendDot(color: .gray.opacity(0.3), label: "No data")
            }
            .font(.caption2)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func miniStat(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func rateColor(_ rate: Double) -> Color {
        rate >= 0.8 ? .green : rate >= 0.5 ? .orange : .red
    }

    private func shiftYear(_ delta: Int) {
        if let next = calendar.date(byAdding: .year, value: delta, to: displayedYear) {
            displayedYear = next
        }
    }

    private func loadYear() async {
        loading = true
        defer { loading = false }

        let year = calendar.component(.year, from: displayedYear)
        var summaries: [MonthSummary] = []
        var totalEvents = 0
        var totalCompleted = 0
        var totalIncomplete = 0
        var monthsWithData = 0
        var busiestMonth: Date?
        var busiestCount = 0
        var bestMonth: Date?
        var bestRate: Double = 0

        for month in 1...12 {
            guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { continue }

            let events = await calendarService.fetchEvents(from: monthStart, to: monthEnd)
            let completed = await reminderService.fetchCompletedCount(from: monthStart, to: monthEnd)
            let incomplete = await reminderService.fetchIncompleteCount(from: monthStart, to: monthEnd)

            let summary = MonthSummary(
                id: monthStart, date: monthStart,
                eventCount: events.count,
                completedCount: completed,
                incompleteCount: incomplete
            )
            summaries.append(summary)

            totalEvents += events.count
            if summary.hasReminderData {
                totalCompleted += completed
                totalIncomplete += incomplete
                monthsWithData += 1
            }

            let monthTotal = events.count + completed + incomplete
            if monthTotal > busiestCount {
                busiestCount = monthTotal
                busiestMonth = monthStart
            }
            if let rate = summary.completionRate, rate > bestRate {
                bestRate = rate
                bestMonth = monthStart
            }
        }

        await MainActor.run {
            monthSummaries = summaries
            stats = YearStats(
                totalEvents: totalEvents,
                totalCompleted: totalCompleted,
                totalIncomplete: totalIncomplete,
                monthsWithData: monthsWithData,
                busiestMonth: busiestMonth,
                busiestMonthCount: busiestCount,
                bestMonth: bestMonth,
                bestRate: bestRate
            )
        }
    }
}
