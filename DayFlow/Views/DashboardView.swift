import SwiftUI

struct DashboardView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(ReminderService.self) private var reminderService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dateHeader
                    statsBar
                    CalendarSection(events: calendarService.events)
                    ReminderSection(reminders: reminderService.reminders) { item in
                        Task { await reminderService.toggleCompletion(item) }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DayFlow")
            .refreshable { await refresh() }
            .task { await requestAccessAndLoad() }
        }
    }

    private var dateHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Date(), format: .dateTime.month(.wide).day())
                    .font(.title2.weight(.bold))
            }
            Spacer()
        }
    }

    private var statsBar: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Events",
                value: "\(calendarService.events.count)",
                icon: "calendar",
                color: .blue
            )
            StatCard(
                title: "Reminders",
                value: "\(reminderService.reminders.count)",
                icon: "checklist",
                color: .green
            )
            StatCard(
                title: "Overdue",
                value: "\(reminderService.reminders.filter(\.isOverdue).count)",
                icon: "exclamationmark.triangle",
                color: .red
            )
        }
    }

    private func requestAccessAndLoad() async {
        await calendarService.requestAccess()
        await reminderService.requestAccess()
    }

    private func refresh() async {
        await calendarService.fetchTodayEvents()
        await reminderService.fetchReminders()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
