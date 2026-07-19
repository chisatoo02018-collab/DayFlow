import SwiftUI

@main
struct DayFlowWatchApp: App {
    @StateObject private var connector = WatchWakeScheduleConnector()

    var body: some Scene {
        WindowGroup {
            WatchWakeTimeView(connector: connector)
        }
    }
}
