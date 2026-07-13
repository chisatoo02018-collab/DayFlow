import AppIntents
import WidgetKit

struct RecordArrivalIntent: AppIntent {
    static let title: LocalizedStringResource = "出社を記録"
    static let description = IntentDescription("現在時刻を出社時刻としてDayFlowに記録します。")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let record = try DayFlowSharedStore.record(.arrive)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(record.arrivedAt?.formatted(date: .omitted, time: .shortened) ?? "現在時刻")に出社を記録しました。")
    }
}

struct RecordDepartureIntent: AppIntent {
    static let title: LocalizedStringResource = "退社を記録"
    static let description = IntentDescription("現在時刻を退社時刻として記録し、勤務区間を今日の実績へ反映します。")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let record = try DayFlowSharedStore.record(.leave)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(record.leftAt?.formatted(date: .omitted, time: .shortened) ?? "現在時刻")に退社を記録しました。")
    }
}

struct DayFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordArrivalIntent(),
            phrases: ["\(.applicationName)で出社を記録"],
            shortTitle: "出社を記録",
            systemImageName: "building.2.fill"
        )
        AppShortcut(
            intent: RecordDepartureIntent(),
            phrases: ["\(.applicationName)で退社を記録"],
            shortTitle: "退社を記録",
            systemImageName: "figure.walk.departure"
        )
        AppShortcut(
            intent: OpenTodayRecordIntent(),
            phrases: ["\(.applicationName)で今日の記録を開く"],
            shortTitle: "今日の記録",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
