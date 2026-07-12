import SwiftUI

struct DayDetailSheet: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(ReminderService.self) private var reminderService
    @Environment(\.dismiss) private var dismiss

    let date: Date
    @State private var events: [CalendarEvent] = []
    @State private var reminders: [ReminderItem] = []
    @State private var loading = true

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty && reminders.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "calendar.badge.minus",
                        description: Text("Nothing scheduled for this day.")
                    )
                } else {
                    List {
                        if !events.isEmpty {
                            Section {
                                ForEach(events) { event in
                                    EventRow(event: event)
                                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                                }
                            } header: {
                                Label("Events", systemImage: "calendar")
                            }
                        }

                        if !reminders.isEmpty {
                            Section {
                                ForEach(reminders) { item in
                                    ReminderRow(item: item) {
                                        Task {
                                            await reminderService.toggleCompletion(item)
                                            await loadData()
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                }
                            } header: {
                                Label("Reminders", systemImage: "checklist")
                            }
                        }
                    }
                }
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadData() }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadData() async {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }

        async let fetchedEvents = calendarService.fetchEvents(from: dayStart, to: dayEnd)
        async let fetchedReminders = reminderService.fetchRemindersForDate(from: dayStart, to: dayEnd)

        let (e, r) = await (fetchedEvents, fetchedReminders)
        await MainActor.run {
            events = e
            reminders = r
            loading = false
        }
    }
}
