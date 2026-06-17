import SwiftUI

struct ReminderSection: View {
    let reminders: [ReminderItem]
    var onToggle: ((ReminderItem) -> Void)?

    private var overdueItems: [ReminderItem] {
        reminders.filter { $0.isOverdue }
    }

    private var activeItems: [ReminderItem] {
        reminders.filter { !$0.isOverdue && !$0.isCompleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Reminders", icon: "checklist", count: reminders.count)

            if reminders.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    if !overdueItems.isEmpty {
                        Text("Overdue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.vertical, 4)

                        ForEach(overdueItems) { item in
                            ReminderRow(item: item) { onToggle?(item) }
                            if item.id != overdueItems.last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }

                        if !activeItems.isEmpty {
                            Divider().padding(.vertical, 4)
                        }
                    }

                    ForEach(activeItems) { item in
                        ReminderRow(item: item) { onToggle?(item) }
                        if item.id != activeItems.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("All caught up!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
