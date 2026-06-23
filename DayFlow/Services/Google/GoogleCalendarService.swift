import Foundation

@Observable
final class GoogleCalendarService {
    private let authManager: GoogleAuthManager
    private let client: GoogleAPIClient

    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
        self.client = GoogleAPIClient(authManager: authManager)
    }

    func fetchEvents(from start: Date, to end: Date) async -> [CalendarEvent] {
        guard authManager.isSignedIn else { return [] }

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        let iso = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: start)),
            URLQueryItem(name: "timeMax", value: iso.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        guard let url = components.url else { return [] }

        do {
            let response: GoogleEventsResponse = try await client.get(url)
            return (response.items ?? []).compactMap(Self.makeEvent)
        } catch {
            return []
        }
    }

    private static func makeEvent(from dto: GoogleEventDTO) -> CalendarEvent? {
        guard let start = parse(dto.start), let end = parse(dto.end) else { return nil }
        return CalendarEvent(
            googleId: dto.id,
            title: dto.summary ?? "No Title",
            startDate: start.date,
            endDate: end.date,
            isAllDay: start.isAllDay,
            calendarTitle: "Google Calendar",
            location: dto.location
        )
    }

    private static func parse(_ dt: GoogleEventDateTime) -> (date: Date, isAllDay: Bool)? {
        if let dateTime = dt.dateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateTime) { return (date, false) }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateTime) { return (date, false) }
            return nil
        }
        if let dateOnly = dt.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            if let date = formatter.date(from: dateOnly) { return (date, true) }
        }
        return nil
    }
}

private struct GoogleEventsResponse: Decodable {
    let items: [GoogleEventDTO]?
}

private struct GoogleEventDTO: Decodable {
    let id: String
    let summary: String?
    let location: String?
    let start: GoogleEventDateTime
    let end: GoogleEventDateTime
}

private struct GoogleEventDateTime: Decodable {
    let date: String?
    let dateTime: String?
}
