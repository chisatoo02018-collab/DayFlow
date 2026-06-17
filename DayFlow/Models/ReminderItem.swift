import Foundation
import EventKit
import SwiftUI

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
    let priority: Int
    let listColor: Color
    let listTitle: String
    let notes: String?

    init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title ?? "No Title"
        self.dueDate = ekReminder.dueDateComponents?.date
        self.isCompleted = ekReminder.isCompleted
        self.priority = ekReminder.priority
        self.listColor = Color(cgColor: ekReminder.calendar.cgColor)
        self.listTitle = ekReminder.calendar.title
        self.notes = ekReminder.notes
    }

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Date()
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
