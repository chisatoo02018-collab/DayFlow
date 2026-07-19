import AppIntents

struct OpenWakeTimeEditorIntent: AppIntent {
    static let title: LocalizedStringResource = "起床時刻を変更"
    static let description = IntentDescription("DayFlowを開き、Watchで起床時刻を変更します。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WatchWakeTimeStore.requestEditor()
        return .result()
    }
}
