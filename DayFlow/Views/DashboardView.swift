import SwiftUI

struct DashboardView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(ReminderService.self) private var reminderService
    @State private var showToast = false
    @State private var toastWorkItem: DispatchWorkItem?
    @State private var showNewItem = false
    @State private var showRescheduleConfirm = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 20) {
                        dateHeader
                        statsBar
                        CalendarSection(events: calendarService.events)
                        ReminderSection(reminders: reminderService.reminders) { item in
                            Task {
                                await reminderService.toggleCompletion(item)
                                showUndoToast()
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, showToast ? 60 : 0)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("DayFlow")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewItem = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showNewItem) {
                    NewItemSheet { await refresh() }
                }
                .refreshable { await refresh() }
                .task { await requestAccessAndLoad() }
                .alert("期限切れのタスクをすべて本日中に変更しますか？", isPresented: $showRescheduleConfirm) {
                    Button("変更する", role: .destructive) {
                        Task {
                            let count = await reminderService.rescheduleOverdueToToday()
                            await calendarService.fetchTodayEvents()
                            if count > 0 {
                                toastWorkItem?.cancel()
                                await MainActor.run {
                                    reminderService.lastAction = nil
                                }
                            }
                        }
                    }
                    Button("キャンセル", role: .cancel) {}
                }

                if showToast, let action = reminderService.lastAction {
                    UndoToastView(
                        message: action.wasCompleted
                            ? "\"\(action.item.title)\" marked incomplete"
                            : "\"\(action.item.title)\" completed",
                        icon: action.wasCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle.fill",
                        iconColor: action.wasCompleted ? .orange : .green,
                        onUndo: {
                            Task {
                                await reminderService.undoLastAction()
                                dismissToast()
                            }
                        },
                        onDismiss: { dismissToast() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showToast)
        }
    }

    private func showUndoToast() {
        toastWorkItem?.cancel()
        withAnimation { showToast = true }
        let work = DispatchWorkItem {
            dismissToast()
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func dismissToast() {
        toastWorkItem?.cancel()
        toastWorkItem = nil
        withAnimation { showToast = false }
        reminderService.dismissAction()
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

    private var overdueCount: Int {
        reminderService.reminders.filter(\.isOverdue).count
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
                value: "\(overdueCount)",
                icon: "exclamationmark.triangle",
                color: .red,
                action: overdueCount > 0 ? { showRescheduleConfirm = true } : nil
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

// MARK: - Toast

struct UndoToastView: View {
    let message: String
    let icon: String
    let iconColor: Color
    var onUndo: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(message)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.blue)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var action: (() -> Void)? = nil

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
            if action != nil {
                Text("Reschedule")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.red, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .onTapGesture { action?() }
    }
}
