import SwiftUI

@main
struct DayFlowApp: App {
    @State private var calendarService = CalendarService()
    @State private var reminderService = ReminderService()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(calendarService)
                .environment(reminderService)
        }
    }
}
