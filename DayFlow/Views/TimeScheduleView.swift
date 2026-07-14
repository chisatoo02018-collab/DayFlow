import SwiftUI

/// The 時間割 tab: pick a day and 予定/実績, paint the 24-hour wheel with categories,
/// and see the per-category breakdown. Edits persist to `ScheduleStore` on every
/// drag release; the record survives app restarts and (Phase 2) mirrors to Obsidian.
struct TimeScheduleView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(VaultWriter.self) private var vault
    @Environment(HealthService.self) private var health

    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var kind: ScheduleKind = .plan
    /// nil = eraser (未設定に戻す).
    @State private var activeCategoryID: String? = TimeCategory.presets.first?.id
    @State private var slots = [String?](repeating: nil, count: slotsPerDay)
    @State private var tagSlots = [Set<String>](repeating: [], count: slotsPerDay)
    @State private var selectedRange: SelectedSlotRange?
    @State private var presentedSheet: EditorSheet?
    @State private var isEditing = false
    @State private var showSyncConfirmation = false
    @State private var showSleepImportAlert = false
    @State private var sleepImportMessage = ""

    init(date: Date = Date(), kind: ScheduleKind = .plan) {
        _date = State(initialValue: Calendar.current.startOfDay(for: date))
        _kind = State(initialValue: kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    kindPicker
                    DateNavigator(
                        date: date,
                        onYesterday: selectYesterday,
                        onToday: selectToday,
                        onTomorrow: selectTomorrow,
                        onCalendar: { presentedSheet = .date }
                    )
                    if canDuplicateFromPlan {
                        DuplicatePlanCard(action: duplicatePlanToActual)
                    }
                    EditingModeControl(
                        isEditing: isEditing,
                        onStart: { isEditing = true },
                        onDone: finishEditing
                    )
                    wheel
                    if isEditing, let selectedRange {
                        TimeRangeEditor(
                            selection: selectedRange,
                            category: store.category(id: selectedRange.categoryID),
                            tagCategories: store.categories.filter { $0.id != selectedRange.categoryID },
                            activeTags: tagsActive(in: selectedRange),
                            onToggleTag: { toggleTag($0, in: selectedRange) },
                            onAdjustStart: adjustSelectedStart,
                            onAdjustEnd: adjustSelectedEnd,
                            onDelete: deleteSelectedRange,
                            onDone: { self.selectedRange = nil }
                        )
                    } else if isEditing {
                        Text("塗った区間をタップすると、開始・終了を細かく調整できます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    categoryStrip
                        .disabled(!isEditing)
                        .opacity(isEditing ? 1 : 0.45)
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
                    Menu {
                        Button("予定パターン", systemImage: "square.stack.3d.up") { presentedSheet = .templates }
                        Button("Obsidianへ同期", systemImage: "arrow.triangle.2.circlepath") { manualSync() }
                            .disabled(!vault.isConfigured)
                        if health.isAvailable {
                            Button("睡眠をヘルスから取り込む", systemImage: "bed.double.fill") {
                                Task { await importSleepFromHealth(auto: false) }
                            }
                            .disabled(kind != .actual)
                            Button("運動をヘルスから取り込む", systemImage: "figure.run") {
                                Task { await importExerciseFromHealth(auto: false) }
                            }
                            .disabled(kind != .actual)
                        }
                        Button("設定", systemImage: "gearshape") { presentedSheet = .settings }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .category:
                    CategoryEditorSheet { name, hex, symbol in
                        let cat = store.addCustomCategory(name: name, colorHex: hex, symbol: symbol)
                        activeCategoryID = cat.id
                    }
                case .settings:
                    SettingsView(writer: vault, health: health)
                case .templates:
                    ScheduleTemplateSheet(
                        templates: store.templates,
                        canSaveCurrent: kind == .plan && assignedMinutes > 0,
                        onApply: applyTemplate,
                        onSave: saveCurrentTemplate,
                        onDelete: store.deleteTemplate
                    )
                case .date:
                    ScheduleDatePickerSheet(date: $date)
                }
            }
            .alert("Obsidianへ同期しました", isPresented: $showSyncConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("詳細な時間割とデイリーノートの DayFlow セクションを更新しました。")
            }
            .alert("ヘルスから取り込み", isPresented: $showSleepImportAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sleepImportMessage)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: date) { _, _ in reload() }
        .onChange(of: kind) { _, _ in reload() }
        .onChange(of: store.externalScheduleRevision) { _, _ in reload() }
        .task(id: DaySchedule.key(date: date, kind: kind)) {
            guard kind == .actual else { return }
            if health.importsSleepToRing { await importSleepFromHealth(auto: true) }
            if health.importsExerciseToRing { await importExerciseFromHealth(auto: true) }
        }
    }

    // MARK: - Sleep import (HealthKit → 実績リング)

    /// Paints the 睡眠 category from HealthKit sleep for the current day's 実績 ring.
    /// HealthKit is authoritative for sleep (existing 睡眠 blocks are replaced), but it
    /// only claims free minutes — a manually painted non-sleep block is never overwritten.
    /// `auto` runs silently on view; the manual menu action reports the result.
    private func importSleepFromHealth(auto: Bool) async {
        guard kind == .actual, health.isAvailable else { return }
        let intervals = await health.sleepIntervals(for: date)
        guard !intervals.isEmpty else {
            if !auto {
                sleepImportMessage = "この日の睡眠データが見つかりませんでした。Apple Watchを着けて就寝すると記録されます。"
                showSleepImportAlert = true
            }
            return
        }

        let sleepID = "sleep"
        var sched = store.schedule(date: date, kind: .actual)
        let before = sleepSignature(sched.blocks)
        sched.blocks.removeAll { $0.categoryID == sleepID }

        let occupied = TimeGrid.slots(from: sched.blocks)
        let dayStart = Calendar.current.startOfDay(for: date)
        var fill = [Bool](repeating: false, count: slotsPerDay)
        for interval in intervals {
            let lo = slotIndex(interval.start, dayStart: dayStart)
            let hi = slotIndex(interval.end, dayStart: dayStart)
            guard lo < hi else { continue }
            for i in lo..<hi where occupied[i] == nil { fill[i] = true }
        }

        var i = 0
        while i < slotsPerDay {
            guard fill[i] else { i += 1; continue }
            var j = i + 1
            while j < slotsPerDay, fill[j] { j += 1 }
            sched.blocks.append(TimeBlock(categoryID: sleepID, start: i * slotMinutes,
                                          end: j * slotMinutes, source: .healthKit))
            i = j
        }

        // Skip persistence when the sleep layout is unchanged, so silent auto-runs on
        // every view don't spin up a redundant Obsidian commit.
        guard sleepSignature(sched.blocks) != before else { return }
        store.save(sched)
        reload()
        mirrorToVault()

        if !auto {
            let totalHours = intervals.reduce(0.0) { $0 + $1.duration } / 3600
            sleepImportMessage = String(format: "睡眠 %.1f 時間を実績リングに反映しました。", totalHours)
            showSleepImportAlert = true
        }
    }

    /// Order-independent fingerprint of the sleep blocks (ignores UUIDs), for change detection.
    private func sleepSignature(_ blocks: [TimeBlock]) -> [String] {
        blocks.filter { $0.categoryID == "sleep" }
            .sorted { $0.start < $1.start }
            .map { "\($0.start)-\($0.end)" }
    }

    private func slotIndex(_ moment: Date, dayStart: Date) -> Int {
        let minutes = Int(moment.timeIntervalSince(dayStart) / 60)
        return min(slotsPerDay, max(0, minutes / slotMinutes))
    }

    /// Reflects HealthKit exercise minutes onto the current 実績 arrays: unaccounted active
    /// time becomes primary 運動, active time that overlaps another activity becomes a 運動
    /// tag on it. Operates on the loaded slot arrays (the view always shows `date`'s 実績
    /// when this runs) and persists through `commit`.
    private func importExerciseFromHealth(auto: Bool) async {
        guard kind == .actual, health.isAvailable else { return }
        let intervals = await health.exerciseIntervals(for: date)  // already merged
        let exerciseID = "exercise"
        let dayStart = Calendar.current.startOfDay(for: date)

        var primary = slots
        var tags = tagSlots
        let beforePrimary = primary
        let beforeTags = tags

        // HealthKit is authoritative for 運動 here, so clear all prior exercise coverage
        // first — otherwise shortened/deleted exercise (or an empty result) leaves stale
        // slots and tags behind. Fresh intervals are then re-applied below.
        for i in primary.indices where primary[i] == exerciseID { primary[i] = nil }
        for i in tags.indices { tags[i].remove(exerciseID) }

        for interval in intervals {
            let lo = slotIndex(interval.start, dayStart: dayStart)
            let hi = slotIndex(interval.end, dayStart: dayStart)
            guard lo < hi else { continue }
            for i in lo..<hi {
                if primary[i] == nil {
                    primary[i] = exerciseID
                } else if primary[i] != exerciseID {
                    tags[i].insert(exerciseID)
                }
            }
        }

        if primary != beforePrimary || tags != beforeTags {
            slots = primary
            tagSlots = tags
            commit()
        }

        if !auto {
            if intervals.isEmpty {
                sleepImportMessage = "この日の運動データが見つかりませんでした。"
            } else {
                let minutes = Int(intervals.reduce(0.0) { $0 + $1.duration } / 60)
                sleepImportMessage = "運動 \(minutes) 分をヘルスから反映しました（他の活動と重なる区間はタグになります）。"
            }
            showSleepImportAlert = true
        }
    }

    // MARK: - Tags on the selected range

    /// Tags present across the whole selected range (intersection), so the chip reflects a
    /// tag that fully covers the block rather than a stray slot.
    private func tagsActive(in range: SelectedSlotRange) -> Set<String> {
        guard range.start < range.end, range.end <= tagSlots.count else { return [] }
        var common = tagSlots[range.start]
        for i in range.start..<range.end { common.formIntersection(tagSlots[i]) }
        return common
    }

    private func toggleTag(_ tag: String, in range: SelectedSlotRange) {
        guard range.start < range.end, range.end <= tagSlots.count else { return }
        let isActive = tagsActive(in: range).contains(tag)
        for i in range.start..<range.end {
            if isActive { tagSlots[i].remove(tag) } else { tagSlots[i].insert(tag) }
        }
        commit()
    }

    // MARK: - Load / save

    private func reload() {
        let blocks = store.schedule(date: date, kind: kind).blocks
        slots = TimeGrid.slots(from: blocks)
        tagSlots = TimeGrid.tagSlots(from: blocks)
        selectedRange = nil
        isEditing = false
    }

    private func commit() {
        var sched = store.schedule(date: date, kind: kind)
        let previous = sched.blocks
        sched.blocks = TimeGrid.blocks(from: slots, tagSlots: tagSlots).map { block in
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
        // Re-derive tag slots from the saved blocks so painted-over/erased tags don't
        // linger in the layer (blocks only carry tags where a primary exists).
        tagSlots = TimeGrid.tagSlots(from: sched.blocks)
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

    private func selectToday() {
        date = Calendar.current.startOfDay(for: Date())
    }

    private func selectYesterday() {
        date = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? date
    }

    private func selectTomorrow() {
        date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? date
    }

    private func finishEditing() {
        selectedRange = nil
        isEditing = false
    }

    private func applyTemplate(_ template: ScheduleTemplate) {
        let blocks = template.blocks.map { block in
            var imported = block
            imported.id = UUID()
            imported.source = .imported
            imported.isUserModified = false
            return imported
        }
        store.save(DaySchedule(date: date, kind: kind, blocks: blocks))
        reload()
        mirrorToVault()
    }

    private func saveCurrentTemplate(_ name: String) {
        store.saveTemplate(name: name, blocks: TimeGrid.blocks(from: slots, source: .imported))
    }

    private func mirrorToVault() {
        guard vault.isConfigured else { return }
        vault.writeDay(date: date,
                       plan: store.schedule(date: date, kind: .plan),
                       actual: store.schedule(date: date, kind: .actual),
                       categories: store.categories)
    }

    /// Offer plan→actual duplication only when recording an actual that's still empty and a
    /// plan for that day exists — the "差分だけ直す" shortcut the 今日タブ points at.
    private var canDuplicateFromPlan: Bool {
        kind == .actual
            && store.hasSchedule(date: date, kind: .plan)
            && !store.hasSchedule(date: date, kind: .actual)
    }

    private func duplicatePlanToActual() {
        store.copySchedule(date: date, from: .plan, to: .actual)
        reload()
        mirrorToVault()
    }

    private func manualSync() {
        mirrorToVault()
        showSyncConfirmation = true
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

    private var wheel: some View {
        ZStack {
            TimeWheelView(slots: $slots, tagSlots: tagSlots, selection: $selectedRange,
                          isEditing: isEditing, activeCategoryID: activeCategoryID,
                          colorFor: colorFor, onCommit: commit)
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
        Button { presentedSheet = .category } label: {
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

            if !tagRows.isEmpty {
                Divider().padding(.vertical, 2)
                Text("タグ（兼ねた活動）").font(.caption).foregroundStyle(.secondary)
                ForEach(tagRows, id: \.id) { row in
                    HStack(spacing: 10) {
                        Image(systemName: "tag.fill").font(.caption2).foregroundStyle(row.color)
                        Text(row.name).font(.subheadline)
                        Spacer()
                        Text(hoursText(row.minutes))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Minutes each tag covers across the day (independent of the primary partition, so
    /// these can sum past the block's own time — that's the point of overlap).
    private var tagRows: [Row] {
        var totals: [String: Int] = [:]
        for set in tagSlots { for tag in set { totals[tag, default: 0] += slotMinutes } }
        return totals
            .sorted { $0.value > $1.value }
            .map { id, mins in
                let cat = store.category(id: id)
                return Row(id: id, name: cat?.name ?? id, color: cat?.color ?? .gray, minutes: mins, percent: 0)
            }
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

private enum EditorSheet: String, Identifiable {
    case category, settings, templates, date
    var id: String { rawValue }
}

private struct TimeRangeEditor: View {
    let selection: SelectedSlotRange
    let category: TimeCategory?
    let tagCategories: [TimeCategory]
    let activeTags: Set<String>
    let onToggleTag: (String) -> Void
    let onAdjustStart: (Int) -> Void
    let onAdjustEnd: (Int) -> Void
    let onDelete: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(category?.name ?? selection.categoryID, systemImage: category?.symbol ?? "clock.fill")
                    .font(.headline)
                    .foregroundStyle(category?.color ?? .gray)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .accessibilityLabel("この区間を削除")
                Button("完了", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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

            tagPicker
        }
        .padding()
        .background((category?.color ?? .gray).opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Toggle secondary tags for this range — e.g. mark a 移動 block as also 運動.
    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("兼ねている活動（タグ）")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tagCategories) { cat in
                        let on = activeTags.contains(cat.id)
                        Button { onToggleTag(cat.id) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: cat.symbol).font(.caption2)
                                Text(cat.name).font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(on ? .white : .primary)
                            .background(on ? cat.color : Color(.tertiarySystemFill), in: Capsule())
                            .overlay(Capsule().stroke(cat.color, lineWidth: on ? 0 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
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

private struct DateNavigator: View {
    let date: Date
    let onYesterday: () -> Void
    let onToday: () -> Void
    let onTomorrow: () -> Void
    let onCalendar: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor)
                    Text(date, format: .dateTime.year().month(.wide).day().weekday(.wide))
                        .font(.headline)
                }
                Spacer()
                Button(action: onCalendar) { Image(systemName: "calendar") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("カレンダーから日付を選ぶ")
            }
            HStack(spacing: 8) {
                DateShortcutButton(title: "昨日", isSelected: Calendar.current.isDateInYesterday(date), action: onYesterday)
                DateShortcutButton(title: "今日", isSelected: Calendar.current.isDateInToday(date), action: onToday)
                DateShortcutButton(title: "明日", isSelected: Calendar.current.isDateInTomorrow(date), action: onTomorrow)
                Spacer()
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusText: String {
        if Calendar.current.isDateInToday(date) { return "今日" }
        if Calendar.current.isDateInYesterday(date) { return "昨日" }
        if Calendar.current.isDateInTomorrow(date) { return "明日" }
        return "選択中の日付"
    }

    private var statusColor: Color {
        if Calendar.current.isDateInToday(date) { return .blue }
        if Calendar.current.isDateInYesterday(date) { return .indigo }
        if Calendar.current.isDateInTomorrow(date) { return .purple }
        return .secondary
    }
}

private struct DateShortcutButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct DuplicatePlanCard: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc.fill")
                .font(.title3).foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("予定から実績を複製")
                    .font(.subheadline.weight(.bold))
                Text("この日の予定をコピーして、違うところだけ直せます")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("複製", action: action)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)
        }
        .padding()
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct EditingModeControl: View {
    let isEditing: Bool
    let onStart: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isEditing ? "pencil.tip.crop.circle.fill" : "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(isEditing ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "編集モード" : "閲覧モード")
                    .font(.subheadline.weight(.bold))
                Text(isEditing ? "リングを塗る・区間を調整できます" : "リングには触れても変更されません")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(isEditing ? "編集を完了" : "編集する", action: isEditing ? onDone : onStart)
                .buttonStyle(.borderedProminent)
                .tint(isEditing ? .orange : .blue)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
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
