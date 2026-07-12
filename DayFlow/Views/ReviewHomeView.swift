import SwiftUI

struct ReviewHomeView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(ReminderService.self) private var reminderService
    @Environment(ScheduleStore.self) private var store

    @Binding var selectedTab: AppTab
    @Binding var recorderDate: Date
    @Binding var recorderKind: ScheduleKind
    @State private var isImporting = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TodayHero(yesterdayRecorded: store.hasSchedule(date: yesterday, kind: .actual))

                    ReviewStepCard(
                        number: 1,
                        eyebrow: "昨日を閉じる",
                        title: store.hasSchedule(date: yesterday, kind: .actual) ? "振り返りは完了" : "昨日の実績を記録",
                        detail: store.hasSchedule(date: yesterday, kind: .actual)
                            ? summary(date: yesterday, kind: .actual)
                            : "予定を複製すれば、差分だけ直して短時間で終えられます。",
                        systemImage: store.hasSchedule(date: yesterday, kind: .actual) ? "checkmark.circle.fill" : "clock.arrow.circlepath",
                        tint: store.hasSchedule(date: yesterday, kind: .actual) ? .green : .indigo,
                        actionTitle: store.hasSchedule(date: yesterday, kind: .actual) ? "確認する" : "記録する",
                        action: openYesterday
                    )

                    ReviewStepCard(
                        number: 2,
                        eyebrow: "今日を組み立てる",
                        title: store.hasSchedule(date: today, kind: .plan) ? "今日の予定は準備済み" : "カレンダーから予定を作成",
                        detail: todayPlanDetail,
                        systemImage: "calendar.badge.clock",
                        tint: .blue,
                        actionTitle: store.hasSchedule(date: today, kind: .plan) ? "予定を調整" : "予定を作る",
                        isLoading: isImporting,
                        action: prepareToday
                    )

                    TodayAgenda(events: calendarService.events, reminders: reminderService.reminders)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DayFlow")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await loadToday() }
            .task { await requestAccessAndLoad() }
        }
    }

    private var todayPlanDetail: String {
        if store.hasSchedule(date: today, kind: .plan) { return summary(date: today, kind: .plan) }
        let count = calendarService.events.filter { !$0.isAllDay }.count
        return count == 0 ? "時刻付きの予定はありません。リングから自由に計画できます。" : "時刻付きの予定 \(count)件を時間割へ取り込みます。"
    }

    private func summary(date: Date, kind: ScheduleKind) -> String {
        let minutes = store.schedule(date: date, kind: kind).assignedMinutes
        let remainder = minutes % 60 == 0 ? "" : " \(minutes % 60)分"
        return "\(minutes / 60)時間\(remainder)を割り当て済み"
    }

    private func openYesterday() {
        recorderDate = yesterday
        recorderKind = .actual
        selectedTab = .record
    }

    private func prepareToday() {
        recorderDate = today
        recorderKind = .plan
        guard !store.hasSchedule(date: today, kind: .plan) else { selectedTab = .record; return }
        isImporting = true
        var slots = [String?](repeating: nil, count: slotsPerDay)
        for event in calendarService.events where !event.isAllDay {
            let start = max(0, Calendar.current.dateComponents([.minute], from: today, to: event.startDate).minute ?? 0)
            let end = min(1440, Calendar.current.dateComponents([.minute], from: today, to: event.endDate).minute ?? 0)
            guard start < end else { continue }
            for index in max(0, start / slotMinutes)..<min(slotsPerDay, Int(ceil(Double(end) / Double(slotMinutes)))) {
                slots[index] = "work"
            }
        }
        store.save(DaySchedule(date: today, kind: .plan,
                               blocks: TimeGrid.blocks(from: slots, source: .calendar)))
        isImporting = false
        selectedTab = .record
    }

    private func requestAccessAndLoad() async {
        await calendarService.requestAccess()
        await reminderService.requestAccess()
    }

    private func loadToday() async {
        await calendarService.fetchTodayEvents()
        await reminderService.fetchReminders()
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

private struct ReviewStepCard: View {
    let number: Int
    let eyebrow: String
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let actionTitle: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("STEP \(number) · \(eyebrow)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(isLoading)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
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
