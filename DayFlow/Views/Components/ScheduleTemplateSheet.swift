import SwiftUI

struct ScheduleTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let templates: [ScheduleTemplate]
    let canSaveCurrent: Bool
    let onApply: (ScheduleTemplate) -> Void
    let onSave: (String) -> Void
    let onDelete: (UUID) -> Void

    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section("予定パターンを呼び出す") {
                    if templates.isEmpty {
                        ContentUnavailableView("保存した予定はありません", systemImage: "square.stack.3d.up", description: Text("現在の予定を名前付きで保存すると、別の日に呼び出せます。"))
                    } else {
                        ForEach(templates) { template in
                            Button {
                                onApply(template)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(template.name).foregroundStyle(.primary)
                                        Text(summary(template)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.down.circle.fill")
                                }
                            }
                            .swipeActions {
                                Button("削除", role: .destructive) { onDelete(template.id) }
                            }
                        }
                    }
                }

                Section("現在の予定を保存") {
                    TextField("例：仕事の日、習い事の日", text: $name)
                    Button("この予定をパターンとして保存") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(!canSaveCurrent || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("予定パターン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func summary(_ template: ScheduleTemplate) -> String {
        let minutes = template.blocks.reduce(0) { $0 + $1.durationMinutes }
        return "\(template.blocks.count)区間 · \(minutes / 60)時間\(minutes % 60 == 0 ? "" : "\(minutes % 60)分")"
    }
}

struct ScheduleDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date

    var body: some View {
        NavigationStack {
            DatePicker("日付", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("日付を選ぶ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("決定") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
