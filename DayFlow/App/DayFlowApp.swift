import SwiftUI

@main
struct DayFlowApp: App {
    @State private var calendarService = CalendarService()
    @State private var reminderService = ReminderService()
    @State private var scheduleStore = ScheduleStore()
    @State private var vaultWriter = VaultWriter()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(calendarService)
                .environment(reminderService)
                .environment(scheduleStore)
                .environment(vaultWriter)
        }
    }
}
