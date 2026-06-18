import SwiftUI

struct ReminderRow: View {
    let item: ReminderItem
    var onToggle: (() -> Void)?
    @State private var animating = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    animating = true
                }
                onToggle?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    animating = false
                }
            }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? .green : item.listColor)
                    .scaleEffect(animating ? 1.3 : 1.0)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: animating)

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
            .opacity(item.isCompleted ? 0.6 : 1.0)

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
        .animation(.easeInOut(duration: 0.25), value: item.isCompleted)
    }
}
