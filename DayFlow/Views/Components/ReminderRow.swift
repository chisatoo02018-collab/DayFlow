import SwiftUI

struct ReminderRow: View {
    let item: ReminderItem
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { onToggle?() }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? .green : item.listColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let due = item.dueDateText {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(due)
                            .font(.caption)
                    }
                    Text(item.listTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(item.isOverdue ? .red : .secondary)
            }

            Spacer()

            if item.priority > 0 {
                HStack(spacing: 1) {
                    ForEach(0..<min(item.priority, 3), id: \.self) { _ in
                        Image(systemName: "exclamationmark")
                            .font(.caption2.weight(.bold))
                    }
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
