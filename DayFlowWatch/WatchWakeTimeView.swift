import SwiftUI

struct WatchWakeTimeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var connector: WatchWakeScheduleConnector
    @State private var isPresentingEditor = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WatchWakeTimeEditor(connector: connector)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("起床予定", systemImage: "alarm.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(connector.selectedTime.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 38, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                            .minimumScaleFactor(0.7)

                        statusLabel
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityLabel("起床予定、\(connector.selectedTime.formatted(date: .omitted, time: .shortened))")
                .accessibilityHint("タップして時刻を変更します")
            }
            .navigationTitle("DayFlow")
        }
        .sheet(isPresented: $isPresentingEditor) {
            NavigationStack {
                WatchWakeTimeEditor(connector: connector)
            }
        }
        .onAppear {
            connector.requestLatestTime()
            openPendingEditor()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { openPendingEditor() }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch connector.syncState {
        case .ready:
            Label("タップして変更", systemImage: "digitalcrown.arrow.clockwise")
                .foregroundStyle(.secondary)
        case .sending:
            Label("iPhoneに設定中…", systemImage: "iphone.and.arrow.forward")
                .foregroundStyle(.blue)
        case .queued:
            Label("iPhone接続時に反映", systemImage: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.yellow)
        case .confirmed:
            Label("Watchの振動を設定済み", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .warning:
            Label("iPhoneでアラームを許可", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        case .failed:
            Label("接続を確認してください", systemImage: "exclamationmark.icloud.fill")
                .foregroundStyle(.red)
        }
    }

    private func openPendingEditor() {
        guard WatchWakeTimeStore.consumeEditorRequest() else { return }
        Task { @MainActor in
            await Task.yield()
            isPresentingEditor = true
        }
    }
}

private struct WatchWakeTimeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var connector: WatchWakeScheduleConnector
    @State private var selectedTime: Date

    init(connector: WatchWakeScheduleConnector) {
        self.connector = connector
        _selectedTime = State(initialValue: connector.selectedTime)
    }

    var body: some View {
        VStack(spacing: 8) {
            DatePicker(
                "起床時刻",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .accessibilityLabel("起床時刻")

            Button {
                connector.setWakeTime(selectedTime)
                dismiss()
            } label: {
                Label("設定", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .navigationTitle("時刻を変更")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    WatchWakeTimeView(connector: WatchWakeScheduleConnector())
}
