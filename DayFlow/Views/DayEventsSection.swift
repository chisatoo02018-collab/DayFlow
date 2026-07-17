import SwiftUI

/// The day's reconstructed life events — purchases and YouTube views read from the vault —
/// shown below the ring/health on the review card. Purchases (day-level) are grouped with a
/// running total; YouTube views (timed) list chronologically, capped so a heavy day stays
/// glanceable. This is the母艦's "1日の復元" surface beyond time and health.
struct DayEventsSection: View {
    let events: [DayEvent]
    let isLoading: Bool

    private static let youtubeCap = 12

    private var purchases: [DayEvent] { events.filter { $0.kind == .purchase } }
    private var youtube: [DayEvent] { events.filter { $0.kind == .youtube } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("この日のできごと").font(.headline)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
            }

            if events.isEmpty {
                Text(isLoading ? "読み込み中…" : "購入・視聴の記録はありません")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !purchases.isEmpty {
                let total = purchases.compactMap(\.amountYen).reduce(0, +)
                groupHeader(
                    "買い物 \(purchases.count)件",
                    trailing: total > 0 ? "¥\(total.formatted())" : nil,
                    systemImage: "cart.fill", tint: .orange
                )
                ForEach(purchases) { p in
                    eventRow(lead: nil, title: p.title, subtitle: p.subtitle,
                             trailing: p.amountYen.map { "¥\($0.formatted())" }, tint: .orange)
                }
            }

            if !youtube.isEmpty {
                groupHeader("YouTube \(youtube.count)本", trailing: nil,
                            systemImage: "play.rectangle.fill", tint: .red)
                ForEach(youtube.prefix(Self.youtubeCap)) { v in
                    eventRow(lead: v.clock, title: v.title, subtitle: v.subtitle,
                             trailing: nil, tint: .red)
                }
                if youtube.count > Self.youtubeCap {
                    Text("ほか \(youtube.count - Self.youtubeCap)本")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func groupHeader(_ title: String, trailing: String?, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private func eventRow(lead: String?, title: String, subtitle: String?,
                          trailing: String?, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let lead {
                Text(lead).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            } else {
                Circle().fill(tint.opacity(0.5)).frame(width: 6, height: 6)
                    .frame(width: 40, alignment: .center).padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.subheadline.monospacedDigit())
            }
        }
    }
}
