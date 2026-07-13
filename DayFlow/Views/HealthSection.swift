import SwiftUI

/// Dashboard card showing today's Apple Watch metrics. Renders nothing when
/// HealthKit is unavailable (e.g. iPad). Missing metrics show a dash.
struct HealthSection: View {
    let snapshot: HealthSnapshot
    let isAvailable: Bool
    /// When non-nil, shows an "Obsidianに記録" button (parent decides availability/feedback).
    var onSync: (() -> Void)? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        if isAvailable {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("ヘルス", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let onSync, snapshot.hasAnyData {
                        Button(action: onSync) {
                            Label("Obsidianに記録", systemImage: "arrow.up.doc")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    HealthMetricTile(title: "歩数", value: format(snapshot.steps), unit: "歩",
                                     icon: "figure.walk", color: .green)
                    HealthMetricTile(title: "安静時心拍", value: format(snapshot.restingHeartRate), unit: "bpm",
                                     icon: "heart.fill", color: .red)
                    HealthMetricTile(title: "平均心拍", value: format(snapshot.averageHeartRate), unit: "bpm",
                                     icon: "waveform.path.ecg", color: .pink)
                    HealthMetricTile(title: "睡眠", value: formatSleep(snapshot.sleepHours), unit: "h",
                                     icon: "bed.double.fill", color: .indigo)
                    HealthMetricTile(title: "消費", value: format(snapshot.activeEnergy), unit: "kcal",
                                     icon: "flame.fill", color: .orange)
                    HealthMetricTile(title: "運動", value: format(snapshot.exerciseMinutes), unit: "分",
                                     icon: "figure.run", color: .mint)
                }
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    private func format(_ value: Int?) -> String {
        value.map { $0.formatted() } ?? "—"
    }

    private func formatSleep(_ hours: Double?) -> String {
        hours.map { String(format: "%.1f", $0) } ?? "—"
    }
}

private struct HealthMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
