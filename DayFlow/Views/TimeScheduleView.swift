import SwiftUI

/// The 時間割 tab: pick a day and 予定/実績, paint the 24-hour wheel with categories,
/// and see the per-category breakdown. Edits persist to `ScheduleStore` on every
/// drag release; the record survives app restarts and (Phase 2) mirrors to Obsidian.
struct TimeScheduleView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(VaultWriter.self) private var vault

    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var kind: ScheduleKind = .plan
    /// nil = eraser (未設定に戻す).
    @State private var activeCategoryID: String? = TimeCategory.presets.first?.id
    @State private var slots = [String?](repeating: nil, count: slotsPerDay)
    @State private var showAddCategory = false
    @State private var showSettings = false
    @State private var selectedRange: SelectedSlotRange?

    init(date: Date = Date(), kind: ScheduleKind = .plan) {
        _date = State(initialValue: Calendar.current.startOfDay(for: date))
        _kind = State(initialValue: kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    kindPicker
                    dateStepper
                    QuickActions(
                        isToday: Calendar.current.isDateInToday(date),
                        isYesterday: Calendar.current.isDateInYesterday(date),
                        canCopyPlan: kind == .actual && store.hasSchedule(date: date, kind: .plan),
                        onToday: { date = Calendar.current.startOfDay(for: Date()) },
                        onYesterday: { date = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? date },
                        onCopyPlan: copyPlanToActual
                    )
                    wheel
                    if let selectedRange {
                        TimeRangeEditor(
                            selection: selectedRange,
                            category: store.category(id: selectedRange.categoryID),
                            onAdjustStart: adjustSelectedStart,
                            onAdjustEnd: adjustSelectedEnd,
                            onDelete: deleteSelectedRange
                        )
                    } else {
                        Text("塗った区間をタップすると、開始・終了を細かく調整できます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    categoryStrip
                    if comparisonMinutes > 0 {
                        ComparisonCard(difference: assignedMinutes - comparisonMinutes, kind: kind)
                    }
                    breakdown
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("時間割")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showAddCategory) {
                CategoryEditorSheet { name, hex, symbol in
                    let cat = store.addCustomCategory(name: name, colorHex: hex, symbol: symbol)
                    activeCategoryID = cat.id
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(writer: vault)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: date) { _, _ in reload() }
        .onChange(of: kind) { _, _ in reload() }
    }

    // MARK: - Load / save

    private func reload() {
        slots = TimeGrid.slots(from: store.schedule(date: date, kind: kind).blocks)
        selectedRange = nil
    }

    private func commit() {
        var sched = store.schedule(date: date, kind: kind)
        let previous = sched.blocks
        sched.blocks = TimeGrid.blocks(from: slots).map { block in
            guard let original = previous
                .filter({ $0.categoryID == block.categoryID })
                .max(by: { overlap($0, block) < overlap($1, block) }),
                  overlap(original, block) > 0 else { return block }
            var updated = block
            updated.source = original.source
            updated.isUserModified = original.isUserModified
                || original.start != block.start
                || original.end != block.end
            return updated
        }
        store.save(sched)
        // Mirror the whole day (both kinds) to Obsidian if configured. No-op otherwise.
        if vault.isConfigured {
            vault.writeDay(date: date,
                           plan: store.schedule(date: date, kind: .plan),
                           actual: store.schedule(date: date, kind: .actual),
                           categories: store.categories)
        }
    }

    private func overlap(_ lhs: TimeBlock, _ rhs: TimeBlock) -> Int {
        max(0, min(lhs.end, rhs.end) - max(lhs.start, rhs.start))
    }

    private func copyPlanToActual() {
        store.copySchedule(date: date, from: .plan, to: .actual)
        reload()
        commit()
    }

    private func adjustSelectedStart(_ delta: Int) {
        guard let range = selectedRange else { return }
        resizeSelected(start: range.start + delta, end: range.end)
    }

    private func adjustSelectedEnd(_ delta: Int) {
        guard let range = selectedRange else { return }
        resizeSelected(start: range.start, end: range.end + delta)
    }

    private func resizeSelected(start: Int, end: Int) {
        guard let old = selectedRange else { return }
        let newStart = min(max(0, start), old.end - 1)
        let newEnd = max(min(slotsPerDay, end), newStart + 1)
        for index in old.start..<old.end where slots[index] == old.categoryID { slots[index] = nil }
        for index in newStart..<newEnd { slots[index] = old.categoryID }
        selectedRange = SelectedSlotRange(start: newStart, end: newEnd, categoryID: old.categoryID)
        commit()
    }

    private func deleteSelectedRange() {
        guard let range = selectedRange else { return }
        for index in range.start..<range.end where slots[index] == range.categoryID { slots[index] = nil }
        selectedRange = nil
        commit()
    }

    private func colorFor(_ id: String) -> Color {
        store.category(id: id)?.color ?? .gray
    }

    // MARK: - Pieces

    private var kindPicker: some View {
        Picker("種別", selection: $kind) {
            ForEach(ScheduleKind.allCases) { k in Text(k.title).tag(k) }
        }
        .pickerStyle(.segmented)
    }

    private var dateStepper: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(date, format: .dateTime.weekday(.wide))
                    .font(.caption).foregroundStyle(.secondary)
                Text(date, format: .dateTime.month().day())
                    .font(.headline)
            }
            Spacer()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 4)
    }

    private func shiftDay(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: delta, to: date) {
            date = Calendar.current.startOfDay(for: d)
        }
    }

    private var wheel: some View {
        ZStack {
            TimeWheelView(slots: $slots, selection: $selectedRange,
                          activeCategoryID: activeCategoryID, colorFor: colorFor, onCommit: commit)
            centerReadout
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 8)
    }

    private var assignedMinutes: Int {
        slots.reduce(0) { $0 + ($1 == nil ? 0 : slotMinutes) }
    }

    private var comparisonMinutes: Int {
        store.schedule(date: date, kind: kind == .plan ? .actual : .plan).assignedMinutes
    }

    private var centerReadout: some View {
        VStack(spacing: 2) {
            Text(hoursText(assignedMinutes))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text("記録済み")
                .font(.caption2).foregroundStyle(.secondary)
            let remaining = 24 * 60 - assignedMinutes
            if remaining > 0 {
                Text("未設定 \(hoursText(remaining))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.categories) { cat in
                    CategoryChip(category: cat, isSelected: activeCategoryID == cat.id) {
                        activeCategoryID = cat.id
                    }
                    .contextMenu {
                        if cat.isCustom {
                            Button(role: .destructive) {
                                store.deleteCustomCategory(id: cat.id)
                                if activeCategoryID == cat.id { activeCategoryID = store.categories.first?.id }
                            } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                }
                eraserChip
                addChip
            }
            .padding(.horizontal, 2)
        }
    }

    private var eraserChip: some View {
        Button { activeCategoryID = nil } label: {
            Label("消す", systemImage: "eraser")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(activeCategoryID == nil ? Color.gray.opacity(0.25) : Color(.secondarySystemGroupedBackground),
                            in: Capsule())
                .overlay(Capsule().stroke(Color.gray.opacity(0.3), lineWidth: activeCategoryID == nil ? 1.5 : 0))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var addChip: some View {
        Button { showAddCategory = true } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("内訳").font(.headline)
            if assignedMinutes == 0 {
                Text("リングをドラッグして時間帯を塗ってください")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(breakdownRows, id: \.id) { row in
                    Button { selectFirstRange(categoryID: row.id) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(row.color).frame(width: 12, height: 12)
                            Text(row.name).font(.subheadline)
                            Spacer()
                            Text(hoursText(row.minutes))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                            Text("\(row.percent)%")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("最初の\(row.name)区間を選択して時刻を編集")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private struct Row: Identifiable { let id: String; let name: String; let color: Color; let minutes: Int; let percent: Int }

    private var breakdownRows: [Row] {
        var totals: [String: Int] = [:]
        for s in slots { if let s { totals[s, default: 0] += slotMinutes } }
        let dayTotal = max(1, totals.values.reduce(0, +))
        return totals
            .sorted { $0.value > $1.value }
            .map { id, mins in
                let cat = store.category(id: id)
                return Row(id: id, name: cat?.name ?? id, color: cat?.color ?? .gray,
                           minutes: mins, percent: Int((Double(mins) / Double(dayTotal) * 100).rounded()))
            }
    }

    private func hoursText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)分" }
        if m == 0 { return "\(h)時間" }
        return "\(h)時間\(m)分"
    }

    private func selectFirstRange(categoryID: String) {
        guard let start = slots.firstIndex(where: { $0 == categoryID }) else { return }
        var end = start + 1
        while end < slots.count, slots[end] == categoryID { end += 1 }
        selectedRange = SelectedSlotRange(start: start, end: end, categoryID: categoryID)
    }
}

private struct TimeRangeEditor: View {
    let selection: SelectedSlotRange
    let category: TimeCategory?
    let onAdjustStart: (Int) -> Void
    let onAdjustEnd: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(category?.name ?? selection.categoryID, systemImage: category?.symbol ?? "clock.fill")
                    .font(.headline)
                    .foregroundStyle(category?.color ?? .gray)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .accessibilityLabel("この区間を削除")
            }

            HStack(spacing: 12) {
                TimeBoundaryControl(
                    title: "開始",
                    value: selection.startMinutes.asClock,
                    onDecrease: { onAdjustStart(-1) },
                    onIncrease: { onAdjustStart(1) }
                )
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TimeBoundaryControl(
                    title: "終了",
                    value: selection.endMinutes.asClock,
                    onDecrease: { onAdjustEnd(-1) },
                    onIncrease: { onAdjustEnd(1) }
                )
            }

            Text("\(durationText(selection.durationMinutes)) · 5分単位")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background((category?.color ?? .gray).opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)分" }
        if minutes % 60 == 0 { return "\(minutes / 60)時間" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }
}

private struct TimeBoundaryControl: View {
    let title: String
    let value: String
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            HStack(spacing: 4) {
                Button(action: onDecrease) { Image(systemName: "minus") }
                Button(action: onIncrease) { Image(systemName: "plus") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QuickActions: View {
    let isToday: Bool
    let isYesterday: Bool
    let canCopyPlan: Bool
    let onToday: () -> Void
    let onYesterday: () -> Void
    let onCopyPlan: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("昨日", action: onYesterday).buttonStyle(.bordered).disabled(isYesterday)
            Button("今日", action: onToday).buttonStyle(.bordered).disabled(isToday)
            Spacer()
            if canCopyPlan {
                Button("予定を複製", systemImage: "doc.on.doc", action: onCopyPlan)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
            }
        }
        .font(.caption.weight(.semibold))
    }
}

private struct ComparisonCard: View {
    let difference: Int
    let kind: ScheduleKind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.title2).foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .actual ? "予定との差" : "実績との差")
                    .font(.caption).foregroundStyle(.secondary)
                Text(message).font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding()
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var message: String {
        if difference == 0 { return "割り当て時間は同じです" }
        let value = abs(difference)
        let duration = value % 60 == 0 ? "\(value / 60)時間" : "\(value / 60)時間\(value % 60)分"
        return difference > 0 ? "比較対象より\(duration)多い" : "比較対象より\(duration)少ない"
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    let category: TimeCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.symbol).font(.caption)
                Text(category.name).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? category.color : Color(.secondarySystemGroupedBackground),
                        in: Capsule())
            .overlay(Capsule().stroke(category.color, lineWidth: isSelected ? 0 : 1.2))
        }
        .buttonStyle(.plain)
    }
}
