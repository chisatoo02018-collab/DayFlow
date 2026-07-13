import SwiftUI

struct WakeTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var scheduleStore
    @State private var customTime = Self.date(hour: 7, minute: 0)
    @State private var isSaving = false
    @State private var errorMessage: String?

    private struct Preset: Identifiable {
        let hour: Int
        let minute: Int
        var id: Int { hour * 60 + minute }
    }

    private static let presets = [
        Preset(hour: 6, minute: 0), Preset(hour: 6, minute: 30),
        Preset(hour: 7, minute: 0), Preset(hour: 7, minute: 30),
        Preset(hour: 8, minute: 0), Preset(hour: 8, minute: 30),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("候補から選ぶ") {
                    ForEach(Self.presets) { preset in
                        Button {
                            save(Self.date(hour: preset.hour, minute: preset.minute))
                        } label: {
                            HStack {
                                Text(Self.label(hour: preset.hour, minute: preset.minute))
                                    .font(.title3.monospacedDigit())
                                Spacer()
                                Image(systemName: "alarm")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .disabled(isSaving)
                    }
                }

                Section("任意の時刻") {
                    DatePicker("起床時刻", selection: $customTime, displayedComponents: .hourAndMinute)
                    Button("この時刻に設定") {
                        save(customTime)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isSaving)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("起床予定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .overlay {
                if isSaving { ProgressView("設定中…") }
            }
        }
        .presentationDetents([.large])
    }

    private func save(_ time: Date) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SetWakeTimeIntent(time: time).perform()
                scheduleStore.reloadFromSharedContainer()
                dismiss()
            } catch {
                errorMessage = "設定できませんでした。アラームの許可を確認して、もう一度お試しください。"
                isSaving = false
            }
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private static func label(hour: Int, minute: Int) -> String {
        String(format: "%d:%02d", hour, minute)
    }
}
