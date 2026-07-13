import AppIntents
import SwiftUI
import WidgetKit

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
