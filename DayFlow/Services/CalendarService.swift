import EventKit
import SwiftUI

@Observable
final class CalendarService {
    private let store = EKEventStore()
    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var events: [CalendarEvent] = []

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            await MainActor.run {
                authorizationStatus = granted ? .fullAccess : .denied
            }
            if granted { await fetchTodayEvents() }
        } catch {
            await MainActor.run { authorizationStatus = .denied }
        }
    }

    func fetchTodayEvents() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        let mapped = ekEvents
            .map { CalendarEvent(from: $0) }
            .sorted { $0.startDate < $1.startDate }

        await MainActor.run { events = mapped }
    }

    func fetchEvents(from start: Date, to end: Date) async -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map { CalendarEvent(from: $0) }
            .sorted { $0.startDate < $1.startDate }
    }
}
