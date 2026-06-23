import EventKit

extension EKReminder {
    /// Matches Apple's Reminders.app: a reminder with a time-of-day due date is overdue
    /// the instant that moment passes, but a date-only due date isn't overdue until the
    /// calendar day itself has elapsed.
    var isOverdue: Bool {
        guard !isCompleted, let components = dueDateComponents, let due = components.date else { return false }

        if components.hour != nil || components.minute != nil {
            return due < Date()
        }

        let calendar = Calendar.current
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: Date())
    }
}
