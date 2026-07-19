import SwiftUI

#if FAMILY_CONTROLS_ENABLED
import DeviceActivity

/// Privacy-preserving Screen Time report rendered by the Device Activity extension.
/// The app receives a view, not exportable activity records.
struct ScreenTimeReportView: View {
    private enum Period: String, CaseIterable, Identifiable {
        case today = "今日"
        case thisWeek = "今週"

        var id: Self { self }
    }

    @State private var period: Period = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("表示期間", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            DeviceActivityReport(.dayFlowSummary, filter: filter)
                .id(period)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("iPhone使用時間レポート")
    }

    private var filter: DeviceActivityFilter {
        let calendar = Calendar.current
        let interval: DateInterval
        switch period {
        case .today:
            interval = calendar.dateInterval(of: .day, for: .now)!
        case .thisWeek:
            interval = calendar.dateInterval(of: .weekOfYear, for: .now)!
        }
        return DeviceActivityFilter(
            segment: period == .today ? .hourly(during: interval) : .daily(during: interval),
            devices: .all
        )
    }
}
#endif
