import SwiftUI
import GoogleSignIn

@main
struct DayFlowApp: App {
    @State private var googleAuthManager: GoogleAuthManager
    @State private var calendarService: CalendarService
    @State private var reminderService: ReminderService

    init() {
        let authManager = GoogleAuthManager()
        let googleCalendarService = GoogleCalendarService(authManager: authManager)
        let googleTasksService = GoogleTasksService(authManager: authManager)

        _googleAuthManager = State(initialValue: authManager)
        _calendarService = State(initialValue: CalendarService(googleService: googleCalendarService))
        _reminderService = State(initialValue: ReminderService(googleService: googleTasksService))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(calendarService)
                .environment(reminderService)
                .environment(googleAuthManager)
                .task { await googleAuthManager.restorePreviousSignIn() }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
