import DeviceActivity
import SwiftUI

@main
struct DayFlowDeviceActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        DayFlowSummaryReportScene()
    }
}

private struct DayFlowSummaryReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .dayFlowSummary
    let content: (DayFlowSummaryConfiguration) -> DayFlowSummaryReportView

    init() {
        content = { configuration in
            DayFlowSummaryReportView(configuration: configuration)
        }
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> DayFlowSummaryConfiguration {
        var totalDuration: TimeInterval = 0
        var categoryDurations = [String: TimeInterval]()

        for await device in data {
            for await segment in device.activitySegments {
                totalDuration += segment.totalActivityDuration
                for await category in segment.categories {
                    let name = category.category.localizedDisplayName ?? "その他"
                    categoryDurations[name, default: 0] += category.totalActivityDuration
                }
            }
        }

        let categories = categoryDurations
            .map { DayFlowCategoryDuration(name: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
        return DayFlowSummaryConfiguration(totalDuration: totalDuration, categories: categories)
    }
}

private struct DayFlowSummaryConfiguration {
    let totalDuration: TimeInterval
    let categories: [DayFlowCategoryDuration]
}

private struct DayFlowCategoryDuration: Identifiable {
    let name: String
    let duration: TimeInterval
    var id: String { name }
}

private struct DayFlowSummaryReportView: View {
    let configuration: DayFlowSummaryConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("使用時間")
                .font(.headline)
            Text(Duration.seconds(configuration.totalDuration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                .font(.title2.weight(.bold))
                .monospacedDigit()

            if configuration.categories.isEmpty {
                Text("この期間のカテゴリ別データはまだありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(configuration.categories.prefix(6)) { category in
                    HStack {
                        Text(category.name)
                        Spacer()
                        Text(Duration.seconds(category.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
    }
}
