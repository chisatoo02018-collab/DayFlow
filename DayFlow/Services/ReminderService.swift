import EventKit
import SwiftUI

@Observable
final class ReminderService {
    private let store = EKEventStore()
    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var reminders: [ReminderItem] = []

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            await MainActor.run {
                authorizationStatus = granted ? .fullAccess : .denied
            }
            if granted { await fetchReminders() }
        } catch {
            await MainActor.run { authorizationStatus = .denied }
        }
    }

    func fetchReminders() async {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
            calendars: nil
        )

        let ekReminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        let mapped = ekReminders
            .map { ReminderItem(from: $0) }
            .sorted { lhs, rhs in
                if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
                guard let ld = lhs.dueDate, let rd = rhs.dueDate else {
                    return lhs.dueDate != nil
                }
                return ld < rd
            }

        await MainActor.run { reminders = mapped }
    }

    func toggleCompletion(_ item: ReminderItem) async {
        let predicate = store.predicateForReminders(in: nil)
        let all = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }
        guard let target = all.first(where: { $0.calendarItemIdentifier == item.id }) else { return }

        target.isCompleted = !target.isCompleted
        try? store.save(target, commit: true)
        await fetchReminders()
    }
}
