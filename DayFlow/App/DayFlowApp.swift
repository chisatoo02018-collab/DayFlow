import SwiftUI
import UIKit

/// Registers HealthKit background delivery at launch — including the silent background
/// relaunches iOS triggers when the watch syncs new data — so the observer is always live.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthBackgroundSync.shared.start()
        return true
    }
}

@main
struct DayFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var calendarService = CalendarService()
    @State private var reminderService = ReminderService()
    @State private var scheduleStore = ScheduleStore()
    @State private var vaultWriter = VaultWriter()
    @State private var healthService = HealthService()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(calendarService)
                .environment(reminderService)
                .environment(scheduleStore)
                .environment(vaultWriter)
                .environment(healthService)
        }
    }
}
