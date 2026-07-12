import SwiftUI

struct InsightsView: View {
    @Environment(ScheduleStore.self) private var store
    @State private var displayedMonth = Date()
    @State private var kind: ScheduleKind = .actual

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    InsightsHeader(month: displayedMonth, onPrevious: { shiftMonth(-1) }, onNext: { shiftMonth(1) })
                    Picker("集計対象", selection: $kind) {
                        ForEach(ScheduleKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    RecordingOverview(recordedDays: schedules.count, totalDays: elapsedDays)
                    CategoryTimeChart(rows: categoryRows, totalMinutes: totalMinutes)
                    PlanActualInsight(planMinutes: planMinutes, actualMinutes: actualMinutes)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("時間の分析")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var interval: DateInterval {
        calendar.dateInterval(of: .month, for: displayedMonth) ?? DateInterval(start: displayedMonth, duration: 0)
    }

    private var schedules: [DaySchedule] {
        store.schedules(from: interval.start, to: interval.end, kind: kind)
    }

    private var elapsedDays: Int {
        if calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) {
            return calendar.component(.day, from: Date())
        }
        return calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 0
    }

    private var totalMinutes: Int { schedules.reduce(0) { $0 + $1.assignedMinutes } }

    private var categoryRows: [CategoryTimeRow] {
        var totals: [String: Int] = [:]
        for schedule in schedules {
            for (id, minutes) in schedule.minutesByCategory { totals[id, default: 0] += minutes }
        }
        return totals.sorted { $0.value > $1.value }.map { id, minutes in
            let category = store.category(id: id)
            return CategoryTimeRow(id: id, name: category?.name ?? id, color: category?.color ?? .gray, minutes: minutes)
        }
    }

    private var planMinutes: Int {
        store.schedules(from: interval.start, to: interval.end, kind: .plan).reduce(0) { $0 + $1.assignedMinutes }
    }

    private var actualMinutes: Int {
        store.schedules(from: interval.start, to: interval.end, kind: .actual).reduce(0) { $0 + $1.assignedMinutes }
    }

    private func shiftMonth(_ value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }
}

private struct InsightsHeader: View {
    let month: Date
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) { Image(systemName: "chevron.left") }
            Spacer()
            Text(month, format: .dateTime.year().month(.wide)).font(.title3.weight(.bold))
            Spacer()
            Button(action: onNext) { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
    }
}

private struct RecordingOverview: View {
    let recordedDays: Int
    let totalDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("記録の継続").font(.caption).foregroundStyle(.secondary)
                    Text("\(recordedDays) / \(totalDays)日").font(.title2.weight(.bold)).monospacedDigit()
                }
                Spacer()
                Text(totalDays == 0 ? "0%" : "\(Int(Double(recordedDays) / Double(totalDays) * 100))%")
                    .font(.title3.weight(.bold)).foregroundStyle(.indigo)
            }
            ProgressView(value: Double(recordedDays), total: Double(max(1, totalDays))).tint(.indigo)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct CategoryTimeRow: Identifiable {
    let id: String
    let name: String
    let color: Color
    let minutes: Int
}

private struct CategoryTimeChart: View {
    let rows: [CategoryTimeRow]
    let totalMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("時間ポートフォリオ").font(.headline)
            if rows.isEmpty {
                ContentUnavailableView("まだ記録がありません", systemImage: "chart.pie", description: Text("実績を記録すると、時間の配分が見えるようになります。"))
                    .frame(minHeight: 170)
            } else {
                ForEach(rows.prefix(8)) { row in
                    VStack(spacing: 6) {
                        HStack {
                            Label(row.name, systemImage: "circle.fill").foregroundStyle(row.color)
                            Spacer()
                            Text(duration(row.minutes)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            Text("\(Int(Double(row.minutes) / Double(max(1, totalMinutes)) * 100))%")
                                .font(.caption).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                        }
                        ProgressView(value: Double(row.minutes), total: Double(max(1, totalMinutes))).tint(row.color)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func duration(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)時間" : "\(minutes / 60)時間\(minutes % 60)分"
    }
}

private struct PlanActualInsight: View {
    let planMinutes: Int
    let actualMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("予定と実績").font(.headline)
            HStack {
                metric("予定", minutes: planMinutes, color: .blue)
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Spacer()
                metric("実績", minutes: actualMinutes, color: .indigo)
            }
            Text(insight).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ label: String, minutes: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(minutes / 60)時間").font(.title3.weight(.bold)).foregroundStyle(color).monospacedDigit()
        }
    }

    private var insight: String {
        guard planMinutes > 0 || actualMinutes > 0 else { return "両方を記録すると、計画の癖が見えるようになります。" }
        let difference = actualMinutes - planMinutes
        if abs(difference) < 60 { return "割り当てた総時間は、予定と実績でほぼ一致しています。" }
        return difference > 0 ? "実績の記録時間が予定より長めです。未計画の時間を確認してみましょう。" : "実績が予定より短めです。未記録の時間がないか確認してみましょう。"
    }
}
