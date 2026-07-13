import SwiftUI

struct MainTabView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .today
    @State private var recorderDate = Date()
    @State private var recorderKind: ScheduleKind = .plan
    @State private var presentedSheet: AppSheet?

    var body: some View {
        TabView(selection: $selectedTab) {
            ReviewHomeView(
                selectedTab: $selectedTab,
                recorderDate: $recorderDate,
                recorderKind: $recorderKind
            )
                .tabItem { Label("今日", systemImage: "sun.max.fill") }
                .tag(AppTab.today)

            TimeScheduleView(date: recorderDate, kind: recorderKind)
                .id("\(DaySchedule.key(date: recorderDate, kind: recorderKind))")
                .tabItem { Label("記録", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.record)

            InsightsView()
                .tabItem { Label("分析", systemImage: "chart.bar.fill") }
                .tag(AppTab.insights)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                scheduleStore.reloadFromSharedContainer()
                handlePendingRoute()
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .wakeTimePicker:
                WakeTimePickerSheet()
            }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-showWakeTimePicker") {
                presentedSheet = .wakeTimePicker
            } else {
                handlePendingRoute()
            }
        }
    }

    private func handlePendingRoute() {
        guard let route = DayFlowSharedStore.consumeRoute() else { return }
        switch route {
        case .todayActual:
            recorderDate = Date()
            recorderKind = .actual
            selectedTab = .record
        case .wakeTimePicker:
            presentedSheet = .wakeTimePicker
        }
    }
}

private enum AppSheet: String, Identifiable {
    case wakeTimePicker
    var id: String { rawValue }
}

enum AppTab: Hashable {
    case today
    case record
    case insights
}
