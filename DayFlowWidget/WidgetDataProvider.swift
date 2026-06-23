import EventKit
import SwiftUI

struct WidgetDataProvider {
    private let store = EKEventStore()

    func fetchTodayEvents(max: Int) -> (events: [WidgetEvent], total: Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return ([], 0) }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let all = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        let mapped = all.prefix(max).map { WidgetEvent(from: $0) }
        return (Array(mapped), all.count)
    }

    func fetchReminders(max: Int) -> (items: [WidgetReminder], total: Int, overdue: Int) {
        let cal = Calendar.current
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: cal.date(byAdding: .month, value: 1, to: Date()),
            calendars: nil
        )

        var items: [WidgetReminder] = []
        var total = 0
        var overdue = 0

        let sem = DispatchSemaphore(value: 0)
        store.fetchReminders(matching: predicate) { fetched in
            if let fetched {
                total = fetched.count
                overdue = fetched.filter(\.isOverdue).count
                items = fetched
                    .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                    .prefix(max)
                    .map { WidgetReminder(from: $0) }
            }
            sem.signal()
        }
        sem.wait()
        return (items, total, overdue)
    }

    func fetchCompletion(from start: Date, to end: Date) -> PeriodCompletion {
        var completed = 0
        var incomplete = 0
        let sem = DispatchSemaphore(value: 0)

        store.fetchReminders(matching: store.predicateForCompletedReminders(
            withCompletionDateStarting: start, ending: end, calendars: nil
        )) { fetched in
            completed = fetched?.count ?? 0
            sem.signal()
        }
        sem.wait()

        store.fetchReminders(matching: store.predicateForIncompleteReminders(
            withDueDateStarting: start, ending: end, calendars: nil
        )) { fetched in
            incomplete = fetched?.count ?? 0
            sem.signal()
        }
        sem.wait()

        return PeriodCompletion(completed: completed, total: completed + incomplete)
    }

    func fetchDailyTrend(days: Int) -> [DailyStats] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        return (0..<days).reversed().compactMap { offset in
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

            let eventCount = store.events(matching: store.predicateForEvents(
                withStart: dayStart, end: dayEnd, calendars: nil
            )).count

            let completion = fetchCompletion(from: dayStart, to: dayEnd)

            return DailyStats(
                id: dayStart, date: dayStart,
                eventCount: eventCount,
                completedCount: completion.completed,
                totalReminderCount: completion.total
            )
        }
    }
}
