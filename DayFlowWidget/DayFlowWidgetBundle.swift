import SwiftUI
import WidgetKit

@main
struct DayFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        DashboardWidget()
        CompletionChartWidget()
        TrendChartWidget()
    }
}
