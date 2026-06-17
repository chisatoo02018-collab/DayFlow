import Foundation
import EventKit
import SwiftUI

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: Color
    let calendarTitle: String
    let location: String?

    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? UUID().uuidString
        self.title = ekEvent.title ?? "No Title"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay
        self.calendarColor = Color(cgColor: ekEvent.calendar.cgColor)
        self.calendarTitle = ekEvent.calendar.title
        self.location = ekEvent.location
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
