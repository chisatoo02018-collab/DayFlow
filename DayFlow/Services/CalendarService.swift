import EventKit
import SwiftUI

@Observable
final class CalendarService {
    private let store = EKEventStore()
    private let googleService: GoogleCalendarService?
    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var events: [CalendarEvent] = []

    init(googleService: GoogleCalendarService? = nil) {
        self.googleService = googleService
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

        let mapped = await fetchEvents(from: startOfDay, to: endOfDay)
        await MainActor.run { events = mapped }
    }

    func fetchEvents(from start: Date, to end: Date) async -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let appleEvents = store.events(matching: predicate).map { CalendarEvent(from: $0) }
        let googleEvents = await googleService?.fetchEvents(from: start, to: end) ?? []
        return (appleEvents + googleEvents).sorted { $0.startDate < $1.startDate }
    }
}
