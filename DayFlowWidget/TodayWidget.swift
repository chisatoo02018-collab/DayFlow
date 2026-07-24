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
            showCalendar: showCal, showReminders: showRem, maxItems: 5,
            workRecord: DayFlowSharedStore.workRecord(), openDestination: config.openDestination
        )
    }
}

struct TodayWidget: Widget {
    let kind = "DashboardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TodayWidgetIntent.self, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DayFlowSharedStore.deepLink(for: .todayActual))
        }
        .configurationDisplayName("今日のDayFlow")
        .description("今日の予定と勤務状況を確認し、出社・退社をすぐ記録できます。")
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

            workStatus

            if entry.workRecord?.isWorking == true {
                Button(intent: RecordDepartureIntent()) {
                    Label("退社を記録", systemImage: "figure.walk.departure")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            } else if entry.workRecord?.leftAt == nil {
                Button(intent: RecordArrivalIntent()) {
                    Label("出社を記録", systemImage: "building.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else if entry.showCalendar, let next = entry.events.first(where: { $0.startDate > Date() }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("次の予定").font(.caption2).foregroundStyle(.secondary)
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
                Text("この先の予定はありません").font(.caption).foregroundStyle(.secondary)
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
        VStack(spacing: 10) {
            HStack {
                workStatus
                Spacer()
                workActionButtons
            }
            Divider()
            HStack(spacing: 12) {
            if entry.showCalendar {
                itemColumn(
                    header: "今日の予定", icon: "calendar", color: .blue,
                    empty: "予定なし"
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
                    header: "タスク", icon: "checklist", color: .green,
                    empty: "完了済み", badge: entry.overdueCount > 0 ? "期限超過 \(entry.overdueCount)" : nil
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

            HStack {
                workStatus
                Spacer()
                workActionButtons
            }

            Divider()

            if entry.showCalendar {
                Label("今日の予定", systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                if entry.events.isEmpty {
                    Text("今日の予定はありません").font(.caption).foregroundStyle(.secondary)
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
                Label("タスク", systemImage: "checklist").font(.caption.weight(.semibold)).foregroundStyle(.green)
                if entry.reminders.isEmpty {
                    Text("すべて完了しています").font(.caption).foregroundStyle(.secondary)
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

    private var workStatus: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let record = entry.workRecord, record.isWorking, let arrived = record.arrivedAt {
                Label("勤務中", systemImage: "briefcase.fill").foregroundStyle(.indigo)
                Text("\(arrived.formatted(date: .omitted, time: .shortened))から")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let left = entry.workRecord?.leftAt {
                Label("退社済み", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(left.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("勤務前", systemImage: "sunrise.fill").foregroundStyle(.blue)
                Text("出社時に記録")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
    }

    private var workActionButtons: some View {
        HStack(spacing: 6) {
            Button(intent: RecordArrivalIntent()) {
                Label("出社", systemImage: "building.2.fill")
            }
            .tint(.blue)
            Button(intent: RecordDepartureIntent()) {
                Label("退社", systemImage: "figure.walk.departure")
            }
            .tint(.indigo)
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
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
