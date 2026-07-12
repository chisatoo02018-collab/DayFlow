import SwiftUI

struct MonthDayData: Identifiable {
    let id: Date
    let date: Date
    let eventCount: Int
    let completedCount: Int
    let incompleteCount: Int
    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var total: Int { completedCount + incompleteCount }
}

struct MonthStats {
    var totalEvents: Int = 0
    var totalCompleted: Int = 0
    var totalIncomplete: Int = 0
    var daysWithData: Int = 0
    var busiestDay: Date?
    var busiestDayCount: Int = 0

    var hasReminderData: Bool { (totalCompleted + totalIncomplete) > 0 }
    var completionRate: Double? {
        let total = totalCompleted + totalIncomplete
        guard total > 0 else { return nil }
        return Double(totalCompleted) / Double(total)
    }
}

struct MonthView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(ReminderService.self) private var reminderService
    @State private var displayedMonth = Date()
    @State private var dayData: [MonthDayData] = []
    @State private var stats = MonthStats()
    @State private var loading = false
    @State private var showNewItem = false
    @State private var selectedDay: MonthDayData?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.veryShortWeekdaySymbols
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthNavigator
                    calendarGrid
                    monthStatsSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewItem = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewItem) {
                NewItemSheet { await loadMonth() }
            }
            .sheet(item: $selectedDay) { day in
                DayDetailSheet(date: day.date)
            }
            .task(id: displayedMonth) { await loadMonth() }
        }
    }

    private var monthNavigator: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            Text(displayedMonth, format: .dateTime.year().month(.wide))
                .font(.title3.weight(.bold))

            Spacer()

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(.horizontal, 4)
    }

    private var calendarGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(gridCells, id: \.offset) { index, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .overlay { if loading { ProgressView() } }
    }

    private var gridCells: [(offset: Int, element: MonthDayData?)] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [MonthDayData?] = Array(repeating: nil, count: offset)
        cells.append(contentsOf: dayData)
        while cells.count % 7 != 0 { cells.append(nil) }
        return Array(cells.enumerated())
    }

    private func dayCell(_ day: MonthDayData) -> some View {
        let hasContent = day.eventCount > 0 || day.total > 0
        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: day.date))")
                .font(.caption.weight(day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? .white : .primary)
                .frame(width: 24, height: 24)
                .background {
                    if day.isToday {
                        Circle().fill(.blue)
                    }
                }

            HStack(spacing: 2) {
                if day.eventCount > 0 {
                    Circle().fill(.blue).frame(width: 4, height: 4)
                }
                if day.completedCount > 0 {
                    Circle().fill(.green).frame(width: 4, height: 4)
                }
                if day.incompleteCount > 0 {
                    Circle().fill(.orange).frame(width: 4, height: 4)
                }
            }
            .frame(height: 6)

            Text(day.total > 0 ? "\(day.completedCount)/\(day.total)" : " ")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(height: 52, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if hasContent { selectedDay = day }
        }
    }

    private var monthStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Summary")
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
                        HStack(spacing: 8) {
                            Text("\(Int(rate * 100))%")
                                .font(.title.weight(.bold))
                                .foregroundStyle(rate >= 0.8 ? .green : rate >= 0.5 ? .orange : .red)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.gray.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(rate >= 0.8 ? .green : rate >= 0.5 ? .orange : .red)
                                        .frame(width: geo.size.width * rate)
                                }
                            }
                            .frame(height: 8)
                        }
                    } else {
                        Text("No data")
                            .font(.subheadline)
                            .foregroundStyle(.gray.opacity(0.5))
                    }
                }

                if let busiest = stats.busiestDay {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Busiest Day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(busiest, format: .dateTime.month(.abbreviated).day())
                            .font(.title3.weight(.bold))
                        Text("\(stats.busiestDayCount) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func loadMonth() async {
        loading = true
        defer { loading = false }

        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return }
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30

        var data: [MonthDayData] = []
        var totalEvents = 0
        var totalCompleted = 0
        var totalIncomplete = 0
        var daysWithData = 0
        var busiestDay: Date?
        var busiestCount = 0

        for dayOffset in 0..<daysInMonth {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: interval.start),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let events = await calendarService.fetchEvents(from: dayStart, to: dayEnd)
            let completed = await reminderService.fetchCompletedCount(from: dayStart, to: dayEnd)
            let incomplete = await reminderService.fetchIncompleteCount(from: dayStart, to: dayEnd)

            let reminderTotal = completed + incomplete
            if reminderTotal > 0 {
                totalCompleted += completed
                totalIncomplete += incomplete
                daysWithData += 1
            }

            let dayTotal = events.count + completed + incomplete
            if dayTotal > busiestCount {
                busiestCount = dayTotal
                busiestDay = dayStart
            }

            totalEvents += events.count

            data.append(MonthDayData(
                id: dayStart, date: dayStart,
                eventCount: events.count,
                completedCount: completed,
                incompleteCount: incomplete
            ))
        }

        await MainActor.run {
            dayData = data
            stats = MonthStats(
                totalEvents: totalEvents,
                totalCompleted: totalCompleted,
                totalIncomplete: totalIncomplete,
                daysWithData: daysWithData,
                busiestDay: busiestDay,
                busiestDayCount: busiestCount
            )
        }
    }
}
