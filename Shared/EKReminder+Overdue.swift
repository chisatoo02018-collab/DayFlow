import EventKit

/// Matches Apple's Reminders.app: a reminder with a time-of-day due date is overdue
/// the instant that moment passes, but a date-only due date isn't overdue until the
/// calendar day itself has elapsed.
enum OverdueRule {
    static func isOverdue(due: Date?, hasTimeComponent: Bool, isCompleted: Bool) -> Bool {
        guard !isCompleted, let due else { return false }

        if hasTimeComponent {
            return due < Date()
        }

        let calendar = Calendar.current
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: Date())
    }
}

extension EKReminder {
    var isOverdue: Bool {
        guard let components = dueDateComponents, let due = components.date else { return false }
        let hasTimeComponent = components.hour != nil || components.minute != nil
        return OverdueRule.isOverdue(due: due, hasTimeComponent: hasTimeComponent, isCompleted: isCompleted)
    }
}
