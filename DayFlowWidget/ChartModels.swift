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

struct CompletionChartEntry: TimelineEntry {
    let date: Date
    let completedCount: Int
    let remainingCount: Int
    let overdueCount: Int

    var total: Int { completedCount + remainingCount }
    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(completedCount) / Double(total)
    }

    static var placeholder: CompletionChartEntry {
        CompletionChartEntry(date: Date(), completedCount: 7, remainingCount: 3, overdueCount: 1)
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
