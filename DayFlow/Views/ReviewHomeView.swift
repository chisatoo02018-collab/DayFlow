import SwiftUI

struct ReviewHomeView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(ReminderService.self) private var reminderService
    @Environment(ScheduleStore.self) private var store
    @Environment(HealthService.self) private var healthService
    @Environment(VaultWriter.self) private var vaultWriter
    @Environment(LocationService.self) private var locationService
    @Environment(PlaceStore.self) private var placeStore

    @Binding var selectedTab: AppTab
    @Binding var recorderDate: Date
    @Binding var recorderKind: ScheduleKind
    @State private var preparingDay: Date?
    @State private var healthSyncMessage: String?
    @State private var showHealthSyncAlert = false

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today) ?? today }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today) ?? today }

    /// Today's attendance, derived from geofence stays. Only shown once an office is set.
    private var attendanceBanner: some View {
        let attended = locationService.didAttendOffice(on: today)
        let minutes = locationService.officeMinutes(on: today)
        let officeName = placeStore.office?.name ?? "職場"
        return HStack(spacing: 12) {
            Image(systemName: attended ? "building.2.fill" : "house.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(attended ? PlaceKind.office.color : PlaceKind.home.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(attended ? "出社" : "在宅・外出")
                    .font(.subheadline.weight(.semibold))
                Text(attended
                     ? "\(officeName)・滞在 \(formatMinutes(minutes))"
                     : "今日はまだ職場での記録がありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)時間\(m)分" }
        if h > 0 { return "\(h)時間" }
        return "\(m)分"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TodayHero(yesterdayRecorded: store.hasSchedule(date: yesterday, kind: .actual))

                    if placeStore.office != nil {
                        attendanceBanner
                    }

                    VStack(spacing: 12) {
                        DayCard(
                            label: "昨日", date: yesterday, kindLabel: "実績",
                            recorded: store.hasSchedule(date: yesterday, kind: .actual),
                            detail: store.hasSchedule(date: yesterday, kind: .actual)
                                ? summary(date: yesterday, kind: .actual)
                                : "リングをなぞって記録。予定があれば編集画面から複製できます。",
                            systemImage: "clock.arrow.circlepath", tint: .indigo,
                            action: { open(day: yesterday, kind: .actual) }
                        )
                        DayCard(
                            label: "今日", date: today, kindLabel: "予定",
                            recorded: store.hasSchedule(date: today, kind: .plan),
                            detail: planDetail(for: today),
                            systemImage: "sun.max.fill", tint: .blue,
                            isLoading: preparingDay == today,
                            action: { prepare(day: today) }
                        )
                        DayCard(
                            label: "明日", date: tomorrow, kindLabel: "予定",
                            recorded: store.hasSchedule(date: tomorrow, kind: .plan),
                            detail: planDetail(for: tomorrow),
                            systemImage: "moon.stars.fill", tint: .purple,
                            isLoading: preparingDay == tomorrow,
                            action: { prepare(day: tomorrow) }
                        )
                    }

                    TodayAgenda(events: calendarService.events, reminders: reminderService.reminders)

                    HealthSection(
                        snapshot: healthService.snapshot,
                        isAvailable: healthService.isAvailable,
                        onSync: syncHealthManually
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DayFlow")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await loadToday() }
            .task { await requestAccessAndLoad() }
            .alert("Obsidian記録", isPresented: $showHealthSyncAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(healthSyncMessage ?? "")
            }
        }
    }

    private func syncHealthManually() {
        vaultWriter.writeHealth(date: Date(), snapshot: healthService.snapshot)
        healthSyncMessage = vaultWriter.isConfigured
            ? "今日のヘルスをデイリーノートの『## ヘルス』に記録しました。"
            : "先に記録タブの設定でVaultまたはGitHubミラーを設定してください。"
        showHealthSyncAlert = true
    }

    private func planDetail(for day: Date) -> String {
        if store.hasSchedule(date: day, kind: .plan) { return summary(date: day, kind: .plan) }
        return "カレンダーの予定を取り込んで、リングで仕上げます。"
    }

    private func summary(date: Date, kind: ScheduleKind) -> String {
        let minutes = store.schedule(date: date, kind: kind).assignedMinutes
        let remainder = minutes % 60 == 0 ? "" : " \(minutes % 60)分"
        return "\(minutes / 60)時間\(remainder)を割り当て済み"
    }

    private func open(day: Date, kind: ScheduleKind) {
        recorderDate = day
        recorderKind = kind
        selectedTab = .record
    }

    /// Quick-entry for a plan day (今日/明日): if the plan is empty, seed it from that day's
    /// calendar events, then jump to the editor. Already-built days just open.
    private func prepare(day: Date) {
        recorderDate = day
        recorderKind = .plan
        guard !store.hasSchedule(date: day, kind: .plan) else { selectedTab = .record; return }
        preparingDay = day
        Task {
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let events = await calendarService.fetchEvents(from: day, to: end)
            store.save(DaySchedule(date: day, kind: .plan, blocks: planBlocks(from: events, day: day)))
            preparingDay = nil
            selectedTab = .record
        }
    }

    /// Time-boxed calendar events → a starting `work` plan for `day` (all-day events skipped).
    private func planBlocks(from events: [CalendarEvent], day: Date) -> [TimeBlock] {
        var slots = [String?](repeating: nil, count: slotsPerDay)
        for event in events where !event.isAllDay {
            let start = max(0, calendar.dateComponents([.minute], from: day, to: event.startDate).minute ?? 0)
            let end = min(1440, calendar.dateComponents([.minute], from: day, to: event.endDate).minute ?? 0)
            guard start < end else { continue }
            for index in max(0, start / slotMinutes)..<min(slotsPerDay, Int(ceil(Double(end) / Double(slotMinutes)))) {
                slots[index] = "work"
            }
        }
        return TimeGrid.blocks(from: slots, source: .calendar)
    }

    private func requestAccessAndLoad() async {
        await calendarService.requestAccess()
        await reminderService.requestAccess()
        await healthService.requestAccess()
        HealthBackgroundSync.shared.start()   // enable background delivery now that access is granted
        syncHealthToVault()
    }

    private func loadToday() async {
        await calendarService.fetchTodayEvents()
        await reminderService.fetchReminders()
        await healthService.refresh()
        syncHealthToVault()
    }

    /// Mirror the fetched metrics into today's Daily note. Only when there's real data,
    /// so an unauthorized or watch-less run never writes an empty block or spins up a commit.
    private func syncHealthToVault() {
        guard healthService.snapshot.hasAnyData else { return }
        vaultWriter.writeHealth(date: Date(), snapshot: healthService.snapshot)
    }
}

private struct TodayHero: View {
    let yesterdayRecorded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date(), format: .dateTime.weekday(.wide))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(Date(), format: .dateTime.month(.wide).day())
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text(yesterdayRecorded ? "昨日を閉じて、今日に集中できます。" : "昨日を振り返ってから、今日を始めましょう。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// One row in the 昨日・今日・明日 strip. Whole card is tappable — jumps to that day's
/// editor (seeding a plan first for empty 今日/明日). Shows a check when already recorded.
private struct DayCard: View {
    let label: String
    let date: Date
    let kindLabel: String
    let recorded: Bool
    let detail: String
    let systemImage: String
    let tint: Color
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(label).font(.subheadline.weight(.bold))
                        Text(date, format: .dateTime.month().day().weekday(.abbreviated))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(kindLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(tint.opacity(0.14), in: Capsule())
                    }
                    Text(detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                if isLoading {
                    ProgressView()
                } else if recorded {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct TodayAgenda: View {
    let events: [CalendarEvent]
    let reminders: [ReminderItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日の流れ").font(.headline)
                Spacer()
                Text("予定 \(events.count) · タスク \(reminders.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if events.isEmpty && reminders.isEmpty {
                ContentUnavailableView("余白のある一日です", systemImage: "sparkles", description: Text("時間割で、自分のための時間を先に確保できます。"))
                    .frame(minHeight: 130)
            } else {
                ForEach(events.prefix(4)) { event in
                    HStack(spacing: 10) {
                        Circle().fill(event.calendarColor).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline.weight(.medium))
                            Text(event.timeRange).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                ForEach(reminders.prefix(3)) { reminder in
                    HStack(spacing: 10) {
                        Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(reminder.isCompleted ? .green : .orange)
                        Text(reminder.title).font(.subheadline)
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}
