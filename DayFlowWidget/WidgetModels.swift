import Foundation
import EventKit
import SwiftUI
import WidgetKit

// MARK: - Shared item models

struct WidgetEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let color: Color

    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? UUID().uuidString
        self.title = ekEvent.title ?? "No Title"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay
        self.color = Color(cgColor: ekEvent.calendar.cgColor)
    }

    var timeText: String {
        if isAllDay { return "All Day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }
}

struct WidgetReminder: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let isOverdue: Bool
    let color: Color

    init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title ?? "No Title"
        self.dueDate = ekReminder.dueDateComponents?.date
        self.isOverdue = ekReminder.isOverdue
        self.color = Color(cgColor: ekReminder.calendar.cgColor)
    }
}

// MARK: - Stats models

struct PeriodCompletion {
    let completed: Int
    let total: Int

    var hasData: Bool { total > 0 }
    var rate: Double? {
        guard total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}

struct DailyStats: Identifiable {
    let id: Date
    let date: Date
    let eventCount: Int
    let completedCount: Int
    let totalReminderCount: Int

    var hasReminderData: Bool { totalReminderCount > 0 }
    var completionRate: Double? {
        guard totalReminderCount > 0 else { return nil }
        return Double(completedCount) / Double(totalReminderCount)
    }
}

// MARK: - Timeline entries

struct TodayEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEvent]
    let reminders: [WidgetReminder]
    let eventCount: Int
    let reminderCount: Int
    let overdueCount: Int
    let showCalendar: Bool
    let showReminders: Bool
    let maxItems: Int

    static var placeholder: TodayEntry {
        TodayEntry(date: Date(), events: [], reminders: [],
                   eventCount: 3, reminderCount: 5, overdueCount: 1,
                   showCalendar: true, showReminders: true, maxItems: 5)
    }
}

struct StatsEntry: TimelineEntry {
    let date: Date
    let day: PeriodCompletion
    let week: PeriodCompletion
    let month: PeriodCompletion
    let year: PeriodCompletion
    let trend: [DailyStats]

    static var placeholder: StatsEntry {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let trend = (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            return DailyStats(id: d, date: d, eventCount: Int.random(in: 1...6),
                              completedCount: Int.random(in: 2...5), totalReminderCount: 8)
        }
        return StatsEntry(
            date: Date(),
            day: PeriodCompletion(completed: 5, total: 8),
            week: PeriodCompletion(completed: 25, total: 40),
            month: PeriodCompletion(completed: 80, total: 120),
            year: PeriodCompletion(completed: 500, total: 800),
            trend: trend
        )
    }
}
