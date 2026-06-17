import SwiftUI
import WidgetKit
import EventKit

struct DashboardProvider: AppIntentTimelineProvider {
    private let store = EKEventStore()

    func placeholder(in context: Context) -> DashboardEntry {
        .placeholder
    }

    func snapshot(for configuration: DashboardWidgetIntent, in context: Context) async -> DashboardEntry {
        fetchEntry(configuration: configuration)
    }

    func timeline(for configuration: DashboardWidgetIntent, in context: Context) async -> Timeline<DashboardEntry> {
        let entry = fetchEntry(configuration: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func fetchEntry(configuration: DashboardWidgetIntent) -> DashboardEntry {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return .placeholder
        }

        let showCalendar = configuration.displayMode != .remindersOnly
        let showReminders = configuration.displayMode != .calendarOnly
        let maxItems = configuration.maxItems.rawValue

        let eventPredicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let ekEvents = store.events(matching: eventPredicate).sorted { $0.startDate < $1.startDate }
        let events = ekEvents.prefix(maxItems).map { WidgetCalendarEvent(from: $0) }

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
                    .prefix(maxItems)
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
            overdueCount: overdueCount,
            showCalendar: showCalendar,
            showReminders: showReminders,
            maxItems: maxItems
        )
    }
}

struct DashboardWidget: Widget {
    let kind = "DashboardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DashboardWidgetIntent.self, provider: DashboardProvider()) { entry in
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

            if entry.showCalendar, let next = entry.events.first(where: { $0.startDate > Date() }) {
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
            } else if entry.showReminders, let first = entry.reminders.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Task")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(first.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(first.isOverdue ? .red : .primary)
                }
            } else {
                Text("No upcoming items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                if entry.showCalendar {
                    Label("\(entry.eventCount)", systemImage: "calendar")
                }
                if entry.showReminders {
                    Label("\(entry.reminderCount)", systemImage: "checklist")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            if entry.showCalendar {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Events", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)

                    if entry.events.isEmpty {
                        Text("No events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entry.events.prefix(entry.maxItems)) { event in
                            HStack(spacing: 6) {
                                Circle().fill(event.color).frame(width: 6, height: 6)
                                Text(event.timeText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)
                                Text(event.title).font(.caption).lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if entry.showCalendar && entry.showReminders {
                Divider()
            }

            if entry.showReminders {
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
                        ForEach(entry.reminders.prefix(entry.maxItems)) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.caption2)
                                    .foregroundStyle(item.color)
                                Text(item.title).font(.caption).lineLimit(1)
                                    .foregroundStyle(item.isOverdue ? .red : .primary)
                            }
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                    if entry.showCalendar {
                        statBadge(value: entry.eventCount, icon: "calendar", color: .blue)
                    }
                    if entry.showReminders {
                        statBadge(value: entry.reminderCount, icon: "checklist", color: .green)
                        if entry.overdueCount > 0 {
                            statBadge(value: entry.overdueCount, icon: "exclamationmark.triangle", color: .red)
                        }
                    }
                }
            }

            Divider()

            if entry.showCalendar {
                Label("Calendar", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)

                if entry.events.isEmpty {
                    Text("No events today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.events.prefix(entry.maxItems)) { event in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).font(.caption.weight(.medium)).lineLimit(1)
                                Text(event.timeText).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 28)
                    }
                }
            }

            if entry.showCalendar && entry.showReminders {
                Divider()
            }

            if entry.showReminders {
                Label("Reminders", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)

                if entry.reminders.isEmpty {
                    Text("All caught up!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.reminders.prefix(entry.maxItems)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .font(.caption2)
                                .foregroundStyle(item.color)
                            Text(item.title).font(.caption).lineLimit(1)
                                .foregroundStyle(item.isOverdue ? .red : .primary)
                            Spacer()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func statBadge(value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text("\(value)").font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
    }
}
