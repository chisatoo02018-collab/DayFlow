import SwiftUI

struct MainTabView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .today
    @State private var recorderDate = Date()
    // The record tab is intentionally actual-first. Plans are entered deliberately
    // from the Today cards, never by footer navigation.
    @State private var recorderKind: ScheduleKind = .actual
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
        .onOpenURL { url in
            guard let route = DayFlowSharedStore.route(from: url) else { return }
            open(route)
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
        open(route)
    }

    private func open(_ route: DayFlowSharedStore.Route) {
        switch route {
        case .today:
            selectedTab = .today
        case .todayActual:
            recorderDate = Date()
            recorderKind = .actual
            selectedTab = .record
        case .insights:
            selectedTab = .insights
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
