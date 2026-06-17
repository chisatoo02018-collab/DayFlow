import Foundation
import WidgetKit

struct DailyStats: Identifiable {
    let id: Date
    let date: Date
    let eventCount: Int
    let completedCount: Int
    let totalReminderCount: Int

    var completionRate: Double {
        guard totalReminderCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalReminderCount)
    }

    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}

struct PeriodCompletion {
    let completed: Int
    let total: Int

    var rate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    static var placeholder: PeriodCompletion {
        PeriodCompletion(completed: 0, total: 0)
    }
}

struct CompletionChartEntry: TimelineEntry {
    let date: Date
    let day: PeriodCompletion
    let week: PeriodCompletion
    let month: PeriodCompletion
    let year: PeriodCompletion

    static var placeholder: CompletionChartEntry {
        CompletionChartEntry(
            date: Date(),
            day: PeriodCompletion(completed: 5, total: 8),
            week: PeriodCompletion(completed: 25, total: 40),
            month: PeriodCompletion(completed: 80, total: 120),
            year: PeriodCompletion(completed: 500, total: 800)
        )
    }
}

struct TrendChartEntry: TimelineEntry {
    let date: Date
    let dailyStats: [DailyStats]

    static var placeholder: TrendChartEntry {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let stats = (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            return DailyStats(id: d, date: d, eventCount: Int.random(in: 1...6),
                              completedCount: Int.random(in: 2...5), totalReminderCount: 8)
        }
        return TrendChartEntry(date: Date(), dailyStats: stats)
    }
}
