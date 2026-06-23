import Foundation
import EventKit
import SwiftUI

enum ReminderSource {
    case apple
    case google
}

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
    let isOverdue: Bool
    let priority: Int
    let listColor: Color
    let listTitle: String
    let notes: String?
    let source: ReminderSource
    /// Only set for Google Tasks items; needed to address the task list when patching completion state.
    let googleTaskListId: String?

    init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title ?? "No Title"
        self.dueDate = ekReminder.dueDateComponents?.date
        self.isCompleted = ekReminder.isCompleted
        self.isOverdue = ekReminder.isOverdue
        self.priority = ekReminder.priority
        self.listColor = Color(cgColor: ekReminder.calendar.cgColor)
        self.listTitle = ekReminder.calendar.title
        self.notes = ekReminder.notes
        self.source = .apple
        self.googleTaskListId = nil
    }

    init(googleTaskId: String, title: String, dueDate: Date?, isCompleted: Bool, notes: String?, listId: String, listTitle: String) {
        self.id = googleTaskId
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        // The Tasks API only ever exposes a date (midnight UTC), never a time of day.
        self.isOverdue = OverdueRule.isOverdue(due: dueDate, hasTimeComponent: false, isCompleted: isCompleted)
        self.priority = 0
        self.listColor = Color(red: 0.26, green: 0.52, blue: 0.96) // Google blue
        self.listTitle = listTitle
        self.notes = notes
        self.source = .google
        self.googleTaskListId = listId
    }

    var dueDateText: String? {
        guard let due = dueDate else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(due) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today \(formatter.string(from: due))"
        } else if calendar.isDateInTomorrow(due) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: due)
        }
    }
}
