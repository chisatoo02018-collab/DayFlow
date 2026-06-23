import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Day", systemImage: "sun.max") }
                .tag(0)

            MonthView()
                .tabItem { Label("Month", systemImage: "calendar") }
                .tag(1)

            YearView()
                .tabItem { Label("Year", systemImage: "chart.bar.xaxis") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
    }
}
