import AppIntents
import SwiftUI
import WidgetKit

private func defaultControlTime(hour: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
}

@available(iOSApplicationExtension 18.0, *)
struct ArrivalControl: ControlWidget {
    let kind = "com.chisatoo.dayflow.arrival"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: RecordArrivalIntent()) {
                Label("出社", systemImage: "building.2.fill")
            }
        }
        .displayName("出社を記録")
        .description("現在時刻を出社時刻として記録します。")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct DepartureControl: ControlWidget {
    let kind = "com.chisatoo.dayflow.departure"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: RecordDepartureIntent()) {
                Label("退社", systemImage: "figure.walk.departure")
            }
        }
        .displayName("退社を記録")
        .description("現在時刻を退社時刻として記録します。")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct WakeTimeControl: ControlWidget {
    let kind = "com.chisatoo.dayflow.wake-time"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: kind, intent: WakeTimeControlConfiguration.self) { configuration in
            ControlWidgetButton(action: SetWakeTimeIntent(time: configuration.time ?? defaultControlTime(hour: 7))) {
                Label("起床予定", systemImage: "alarm.waves.left.and.right.fill")
            }
        }
        .displayName("起床予定")
        .description("長押しで起床時刻を設定し、タップで睡眠予定とアラームを登録します。")
        .promptsForUserConfiguration()
    }
}

@available(iOSApplicationExtension 18.0, *)
struct BedtimeControl: ControlWidget {
    let kind = "com.chisatoo.dayflow.bedtime"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: kind, intent: BedtimeControlConfiguration.self) { configuration in
            ControlWidgetButton(action: SetBedtimeIntent(time: configuration.time ?? defaultControlTime(hour: 23))) {
                Label("就寝予定", systemImage: "bed.double.fill")
            }
        }
        .displayName("就寝予定")
        .description("長押しで就寝時刻を設定し、タップで今日の睡眠予定へ登録します。")
        .promptsForUserConfiguration()
    }
}

@available(iOSApplicationExtension 18.0, *)
struct TodayRecordControl: ControlWidget {
    let kind = "com.chisatoo.dayflow.today-record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: OpenTodayRecordIntent()) {
                Label("今日の記録", systemImage: "clock.arrow.circlepath")
            }
        }
        .displayName("今日の記録")
        .description("DayFlowを今日の実績リングで開きます。")
    }
}
