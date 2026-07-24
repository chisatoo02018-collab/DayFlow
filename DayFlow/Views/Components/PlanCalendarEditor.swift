import SwiftUI

/// A day timeline for plans. It deliberately looks and behaves like calendar event
/// registration: appointments have titles, start/end times, a category colour, and a
/// clear add button. Actuals stay on the radial record editor.
struct PlanCalendarEditor: View {
    @Binding var blocks: [TimeBlock]
    let date: Date
    let categories: [TimeCategory]
    let onSave: () -> Void

    @State private var editing: TimeBlock?
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("予定")
                        .font(.headline)
                    Text("カレンダーと同じ感覚で予定を登録できます")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { creating = true } label: { Label("追加", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }

            if blocks.isEmpty {
                ContentUnavailableView("予定がありません", systemImage: "calendar.badge.plus",
                                       description: Text("右上の追加から最初の予定を登録します。"))
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedBlocks) { block in
                        Button { editing = block } label: { eventRow(block) }
                            .buttonStyle(.plain)
                        if block.id != sortedBlocks.last?.id { Divider().padding(.leading, 58) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sheet(item: $editing) { block in
            PlanEventSheet(date: date, categories: categories, initial: block) { updated in
                replace(updated)
            } onDelete: {
                blocks.removeAll { $0.id == block.id }
                onSave()
            }
        }
        .sheet(isPresented: $creating) {
            PlanEventSheet(date: date, categories: categories, initial: nil) { created in
                blocks.append(created)
                blocks.sort { $0.start < $1.start }
                onSave()
            }
        }
    }

    private var sortedBlocks: [TimeBlock] { blocks.sorted { $0.start < $1.start } }

    private func eventRow(_ block: TimeBlock) -> some View {
        HStack(spacing: 12) {
            Text("\(block.start.asClock)\n\(block.end.asClock)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            RoundedRectangle(cornerRadius: 3).fill(category(block.categoryID)?.color ?? .gray).frame(width: 4, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title?.isEmpty == false ? block.title! : category(block.categoryID)?.name ?? "予定")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(category(block.categoryID)?.name ?? block.categoryID)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    private func replace(_ updated: TimeBlock) {
        guard let index = blocks.firstIndex(where: { $0.id == updated.id }) else { return }
        blocks[index] = updated
        blocks.sort { $0.start < $1.start }
        onSave()
    }

    private func category(_ id: String) -> TimeCategory? { categories.first { $0.id == id } }
}

private struct PlanEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let categories: [TimeCategory]
    let initial: TimeBlock?
    let onSave: (TimeBlock) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var title = ""
    @State private var categoryID = TimeCategory.presets.first?.id ?? "work"
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)

    var body: some View {
        NavigationStack {
            Form {
                Section("予定") { TextField("タイトル", text: $title) }
                Section("時間") {
                    DatePicker("開始", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("終了", selection: $end, in: start..., displayedComponents: .hourAndMinute)
                }
                Section("色分け") {
                    Picker("カテゴリ", selection: $categoryID) {
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbol).tag(category.id)
                        }
                    }
                }
                if initial != nil { Section { Button("予定を削除", role: .destructive) { onDelete?(); dismiss() } } }
            }
            .navigationTitle(initial == nil ? "予定を追加" : "予定を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(end <= start) }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        let day = Calendar.current.startOfDay(for: date)
        if let initial {
            title = initial.title ?? ""
            categoryID = initial.categoryID
            start = day.addingTimeInterval(TimeInterval(initial.start * 60))
            end = day.addingTimeInterval(TimeInterval(initial.end * 60))
        } else {
            let now = Date()
            start = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: now), minute: 0, second: 0, of: day) ?? day
            end = start.addingTimeInterval(3600)
        }
    }

    private func save() {
        let day = Calendar.current.startOfDay(for: date)
        let minutes: (Date) -> Int = { max(0, min(1440, Calendar.current.dateComponents([.minute], from: day, to: $0).minute ?? 0)) }
        onSave(TimeBlock(id: initial?.id ?? UUID(), categoryID: categoryID,
                         title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title,
                         start: minutes(start), end: minutes(end), source: initial?.source ?? .manual,
                         isUserModified: initial != nil))
        dismiss()
    }
}
