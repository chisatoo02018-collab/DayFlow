import SwiftUI
import WidgetKit
import EventKit

struct DashboardProvider: TimelineProvider {
    private let store = EKEventStore()

    func placeholder(in context: Context) -> DashboardEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchEntry() -> DashboardEntry {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return .placeholder
        }

        let eventPredicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let ekEvents = store.events(matching: eventPredicate)
            .sorted { $0.startDate < $1.startDate }

        let events = ekEvents.prefix(6).map { WidgetCalendarEvent(from: $0) }

        var reminders: [WidgetReminderItem] = []
        var reminderCount = 0
        var overdueCount = 0

        let semaphore = DispatchSemaphore(value: 0)
        let reminderPredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: calendar.date(byAdding: .month, value: 1, to: Date()),
            calendars: nil
        )
        store.fetchReminders(matching: reminderPredicate) { fetched in
            if let fetched {
                reminderCount = fetched.count
                overdueCount = fetched.filter {
                    guard let due = $0.dueDateComponents?.date else { return false }
                    return due < Date() && !$0.isCompleted
                }.count
                reminders = fetched
                    .sorted {
                        ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture)
                    }
                    .prefix(5)
                    .map { WidgetReminderItem(from: $0) }
            }
            semaphore.signal()
        }
        semaphore.wait()

        return DashboardEntry(
            date: Date(),
            events: Array(events),
            reminders: reminders,
            eventCount: ekEvents.count,
            reminderCount: reminderCount,
            overdueCount: overdueCount
        )
    }
}

struct DashboardWidget: Widget {
    let kind = "DashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardProvider()) { entry in
            DashboardWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("DayFlow Dashboard")
        .description("View today's calendar events and reminders at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DashboardWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DashboardEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Date(), format: .dateTime.weekday(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date(), format: .dateTime.day())
                    .font(.title.weight(.bold))
            }

            Divider()

            if let next = entry.events.first(where: { $0.startDate > Date() }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(next.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text(next.timeText)
                        .font(.caption)
                        .foregroundStyle(next.color)
                }
            } else {
                Text("No upcoming events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Label("\(entry.eventCount)", systemImage: "calendar")
                Label("\(entry.reminderCount)", systemImage: "checklist")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Events", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)

                if entry.events.isEmpty {
                    Text("No events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.events.prefix(3)) { event in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(event.color)
                                .frame(width: 6, height: 6)
                            Text(event.timeText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            Text(event.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Reminders", systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    if entry.overdueCount > 0 {
                        Text("\(entry.overdueCount) overdue")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                if entry.reminders.isEmpty {
                    Text("All done!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.reminders.prefix(3)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .font(.caption2)
                                .foregroundStyle(item.color)
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(item.isOverdue ? .red : .primary)
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(Date(), format: .dateTime.weekday(.wide))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Date(), format: .dateTime.month(.wide).day())
                        .font(.title3.weight(.bold))
                }
                Spacer()
                HStack(spacing: 16) {
                    statBadge(value: entry.eventCount, icon: "calendar", color: .blue)
                    statBadge(value: entry.reminderCount, icon: "checklist", color: .green)
                    if entry.overdueCount > 0 {
                        statBadge(value: entry.overdueCount, icon: "exclamationmark.triangle", color: .red)
                    }
                }
            }

            Divider()

            Label("Calendar", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)

            if entry.events.isEmpty {
                Text("No events today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.events.prefix(4)) { event in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(event.color)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(event.timeText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 28)
                }
            }

            Divider()

            Label("Reminders", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

            if entry.reminders.isEmpty {
                Text("All caught up!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.reminders.prefix(4)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .foregroundStyle(item.color)
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(item.isOverdue ? .red : .primary)
                        Spacer()
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func statBadge(value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(value)")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
    }
}
