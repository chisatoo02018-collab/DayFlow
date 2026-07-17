import SwiftUI
import WidgetKit

@main
struct DayFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        StatsWidget()
        TypicalDayWidget()
        if #available(iOSApplicationExtension 18.0, *) {
            ArrivalControl()
            DepartureControl()
            BedtimeControl()
            TodayRecordControl()
        }
        if #available(iOSApplicationExtension 26.0, *) {
            WakeTimeControl()
        }
    }
}
