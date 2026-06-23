import Foundation
import EventKit
import SwiftUI

enum EventSource {
    case apple
    case google
}

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: Color
    let calendarTitle: String
    let location: String?
    let source: EventSource

    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? UUID().uuidString
        self.title = ekEvent.title ?? "No Title"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay
        self.calendarColor = Color(cgColor: ekEvent.calendar.cgColor)
        self.calendarTitle = ekEvent.calendar.title
        self.location = ekEvent.location
        self.source = .apple
    }

    init(googleId: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool, calendarTitle: String, location: String?) {
        self.id = googleId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarColor = Color(red: 0.26, green: 0.52, blue: 0.96) // Google blue
        self.calendarTitle = calendarTitle
        self.location = location
        self.source = .google
    }

    var timeRange: String {
        if isAllDay { return "All Day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    var isNow: Bool {
        let now = Date()
        return startDate <= now && now <= endDate
    }
}
