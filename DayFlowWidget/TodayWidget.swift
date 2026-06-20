import SwiftUI
import WidgetKit

struct TodayProvider: AppIntentTimelineProvider {
    private let data = WidgetDataProvider()

    func placeholder(in context: Context) -> TodayEntry { .placeholder }

    func snapshot(for configuration: TodayWidgetIntent, in context: Context) async -> TodayEntry {
        fetchEntry(configuration)
    }

    func timeline(for configuration: TodayWidgetIntent, in context: Context) async -> Timeline<TodayEntry> {
        let entry = fetchEntry(configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func fetchEntry(_ config: TodayWidgetIntent) -> TodayEntry {
        let showCal = config.displayMode != .remindersOnly
        let showRem = config.displayMode != .calendarOnly

        let (events, eventTotal) = data.fetchTodayEvents(max: 5)
        let (reminders, remTotal, overdueTotal) = data.fetchReminders(max: 5)

        return TodayEntry(
            date: Date(), events: events, reminders: reminders,
            eventCount: eventTotal, reminderCount: remTotal, overdueCount: overdueTotal,
            showCalendar: showCal, showReminders: showRem, maxItems: 5
        )
    }
}

struct TodayWidget: Widget {
    let kind = "DashboardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TodayWidgetIntent.self, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("DayFlow Today")
        .description("Today's events and reminders at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemLarge: largeView
        default: mediumView
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
                    Text("Next").font(.caption2).foregroundStyle(.secondary)
                    Text(next.title).font(.subheadline.weight(.medium)).lineLimit(2)
                    Text(next.timeText).font(.caption).foregroundStyle(next.color)
                }
            } else if entry.showReminders, let first = entry.reminders.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Task").font(.caption2).foregroundStyle(.secondary)
                    Text(first.title).font(.subheadline.weight(.medium)).lineLimit(2)
                        .foregroundStyle(first.isOverdue ? .red : .primary)
                }
            } else {
                Text("No upcoming items").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                if entry.showCalendar { Label("\(entry.eventCount)", systemImage: "calendar") }
                if entry.showReminders { Label("\(entry.reminderCount)", systemImage: "checklist") }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            if entry.showCalendar {
                itemColumn(
                    header: "Events", icon: "calendar", color: .blue,
                    empty: "No events"
                ) {
                    ForEach(entry.events.prefix(4)) { event in
                        HStack(spacing: 6) {
                            Circle().fill(event.color).frame(width: 6, height: 6)
                            Text(event.timeText).font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            Text(event.title).font(.caption).lineLimit(1)
                        }
                    }
                }
            }

            if entry.showCalendar && entry.showReminders { Divider() }

            if entry.showReminders {
                itemColumn(
                    header: "Reminders", icon: "checklist", color: .green,
                    empty: "All done!", badge: entry.overdueCount > 0 ? "\(entry.overdueCount) overdue" : nil
                ) {
                    ForEach(entry.reminders.prefix(4)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "circle").font(.caption2).foregroundStyle(item.color)
                            Text(item.title).font(.caption).lineLimit(1)
                                .foregroundStyle(item.isOverdue ? .red : .primary)
                        }
                    }
                }
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(Date(), format: .dateTime.weekday(.wide)).font(.caption).foregroundStyle(.secondary)
                    Text(Date(), format: .dateTime.month(.wide).day()).font(.title3.weight(.bold))
                }
                Spacer()
                HStack(spacing: 16) {
                    if entry.showCalendar { badge(entry.eventCount, icon: "calendar", color: .blue) }
                    if entry.showReminders {
                        badge(entry.reminderCount, icon: "checklist", color: .green)
                        if entry.overdueCount > 0 { badge(entry.overdueCount, icon: "exclamationmark.triangle", color: .red) }
                    }
                }
            }

            Divider()

            if entry.showCalendar {
                Label("Calendar", systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                if entry.events.isEmpty {
                    Text("No events today").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entry.events.prefix(5)) { event in
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

            if entry.showCalendar && entry.showReminders { Divider() }

            if entry.showReminders {
                Label("Reminders", systemImage: "checklist").font(.caption.weight(.semibold)).foregroundStyle(.green)
                if entry.reminders.isEmpty {
                    Text("All caught up!").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entry.reminders.prefix(5)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "circle").font(.caption2).foregroundStyle(item.color)
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

    private func itemColumn<Content: View>(
        header: String, icon: String, color: Color,
        empty: String, badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(header, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
                Spacer()
                if let badge { Text(badge).font(.caption2).foregroundStyle(.red) }
            }
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(_ value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text("\(value)").font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
    }
}
