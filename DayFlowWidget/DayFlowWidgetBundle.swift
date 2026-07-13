import SwiftUI
import WidgetKit

@main
struct DayFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        StatsWidget()
        if #available(iOSApplicationExtension 18.0, *) {
            ArrivalControl()
            DepartureControl()
        }
    }
}
