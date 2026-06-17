import SwiftUI

struct CalendarSection: View {
    let events: [CalendarEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Calendar", icon: "calendar", count: events.count)

            if events.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(events) { event in
                        EventRow(event: event)
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
            Image(systemName: "calendar.badge.checkmark")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No events today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
