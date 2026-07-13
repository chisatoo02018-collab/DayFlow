import AppIntents
import Foundation
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
#endif

@available(iOS 18.0, *)
@available(iOSApplicationExtension 18.0, *)
struct WakeTimeControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "起床予定の設定"

    @Parameter(title: "起床時刻")
    var time: Date?
}

@available(iOS 18.0, *)
@available(iOSApplicationExtension 18.0, *)
struct BedtimeControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "就寝予定の設定"

    @Parameter(title: "就寝時刻")
    var time: Date?
}

struct DayFlowAlarmMetadata: Codable, Hashable, Sendable {
    let kind: String
}

@available(iOS 26.0, *)
extension DayFlowAlarmMetadata: AlarmMetadata {}

struct SetWakeTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "起床予定を設定"
    static let description = IntentDescription("起床予定をDayFlowへ記録し、次の指定時刻にアラームを設定します。")
    static let openAppWhenRun = false

    @Parameter(title: "起床時刻")
    var time: Date

    init() {}
    init(time: Date) { self.time = time }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        DayFlowSharedStore.recordPlannedSleepEdge(time: time, isWakeTime: true)
        guard #available(iOS 26.0, *) else {
            return .result(dialog: "起床予定を記録しました。アラーム設定にはiOS 26以降が必要です。")
        }
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined {
            _ = try await manager.requestAuthorization()
        }
        guard manager.authorizationState == .authorized else {
            return .result(dialog: "起床予定は記録しましたが、アラームの許可がオフです。設定アプリでDayFlowのアラームを許可してください。")
        }

        let next = Self.nextOccurrence(of: time)
        let stopButton = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill")
        let presentation = AlarmPresentation(alert: .init(title: "DayFlow 起床予定", stopButton: stopButton))
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: DayFlowAlarmMetadata(kind: "wake"),
            tintColor: .indigo
        )
        let configuration = AlarmManager.AlarmConfiguration<DayFlowAlarmMetadata>.alarm(
            schedule: .fixed(next), attributes: attributes
        )
        _ = try await manager.schedule(id: UUID(), configuration: configuration)
        return .result(dialog: "\(next.formatted(date: .abbreviated, time: .shortened))に起床アラームを設定しました。")
    }

    private static func nextOccurrence(of time: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let today = calendar.date(bySettingHour: components.hour ?? 7,
                                  minute: components.minute ?? 0,
                                  second: 0, of: Date()) ?? Date()
        return today > Date() ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

struct SetBedtimeIntent: AppIntent {
    static let title: LocalizedStringResource = "就寝予定を設定"
    static let description = IntentDescription("指定時刻から24時までを今日の睡眠予定として記録します。")
    static let openAppWhenRun = false

    @Parameter(title: "就寝時刻")
    var time: Date

    init() {}
    init(time: Date) { self.time = time }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        DayFlowSharedStore.recordPlannedSleepEdge(time: time, isWakeTime: false)
        return .result(dialog: "今日の就寝予定を\(time.formatted(date: .omitted, time: .shortened))に設定しました。")
    }
}

struct OpenTodayRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "今日の記録を開く"
    static let description = IntentDescription("DayFlowを今日の実績リングで開きます。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        DayFlowSharedStore.requestRoute(.todayActual)
        return .result()
    }
}
