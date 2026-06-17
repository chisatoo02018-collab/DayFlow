import Foundation
import EventKit
import SwiftUI
import WidgetKit

struct WidgetCalendarEvent: Identifiable {
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

struct WidgetReminderItem: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let isOverdue: Bool
    let color: Color

    init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title ?? "No Title"
        self.dueDate = ekReminder.dueDateComponents?.date
        self.isOverdue = {
            guard let due = ekReminder.dueDateComponents?.date else { return false }
            return due < Date() && !ekReminder.isCompleted
        }()
        self.color = Color(cgColor: ekReminder.calendar.cgColor)
    }
}

struct DashboardEntry: TimelineEntry {
    let date: Date
    let events: [WidgetCalendarEvent]
    let reminders: [WidgetReminderItem]
    let eventCount: Int
    let reminderCount: Int
    let overdueCount: Int
    let showCalendar: Bool
    let showReminders: Bool
    let maxItems: Int

    static var placeholder: DashboardEntry {
        DashboardEntry(
            date: Date(),
            events: [],
            reminders: [],
            eventCount: 3,
            reminderCount: 5,
            overdueCount: 1,
            showCalendar: true,
            showReminders: true,
            maxItems: 5
        )
    }
}
