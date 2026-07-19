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
    @State private var scheduleStore: ScheduleStore
    @State private var vaultWriter = VaultWriter()
    @State private var healthService = HealthService()
    @State private var photoMetadataService = PhotoMetadataService()
    @State private var screenTimeService = ScreenTimeService()
    @State private var placeStore = PlaceStore()
    @State private var locationService: LocationService

    init() {
        let scheduleStore = ScheduleStore()
        let store = PlaceStore()
        _scheduleStore = State(initialValue: scheduleStore)
        _placeStore = State(initialValue: store)
        _locationService = State(initialValue: LocationService(placeStore: store))
        WatchWakeScheduleCoordinator.shared.configure(scheduleStore: scheduleStore)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(calendarService)
                .environment(reminderService)
                .environment(scheduleStore)
                .environment(vaultWriter)
                .environment(healthService)
                .environment(photoMetadataService)
                .environment(screenTimeService)
                .environment(placeStore)
                .environment(locationService)
                // Geofences must be (re)registered on every cold start, including the
                // background relaunches iOS performs after a crossing.
                .task { locationService.refreshMonitoring() }
                // This checks the existing Photos decision only; it never prompts on launch.
                .task { await photoMetadataService.refreshIfAuthorized() }
        }
    }
}
