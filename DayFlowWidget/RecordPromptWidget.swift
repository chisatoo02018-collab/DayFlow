import SwiftUI
import WidgetKit

/// A deliberately quiet entry point: it answers only "what should I record now?"
/// and always opens today's actual ring, never the planning surface.
struct RecordPromptEntry: TimelineEntry {
    let date: Date
    let workRecord: WorkdayRecord?

    static let placeholder = RecordPromptEntry(date: Date(), workRecord: nil)
}

struct RecordPromptProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordPromptEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (RecordPromptEntry) -> Void) {
        completion(RecordPromptEntry(date: Date(), workRecord: DayFlowSharedStore.workRecord()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordPromptEntry>) -> Void) {
        let entry = RecordPromptEntry(date: Date(), workRecord: DayFlowSharedStore.workRecord())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct RecordPromptWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecordPromptWidget", provider: RecordPromptProvider()) { entry in
            RecordPromptView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DayFlowSharedStore.deepLink(for: .todayActual))
        }
        .configurationDisplayName("今を記録")
        .description("今日の実績をすぐ記録します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RecordPromptView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecordPromptEntry

    private var title: String {
        guard let record = entry.workRecord else { return "今の流れを記録" }
        if record.isWorking { return "勤務中の実績を整える" }
        if record.leftAt != nil { return "今日を振り返る" }
        return "今の流れを記録"
    }

    private var detail: String {
        guard let record = entry.workRecord else { return "リングをなぞって、実際の一日を残そう" }
        if record.arrivedAt != nil, record.isWorking {
            return "勤務中。実績を追記しよう"
        }
        if record.leftAt != nil { return "退社済み。今日を振り返ろう" }
        return "リングをなぞって、実際の一日を残そう"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(family == .systemSmall ? 3 : 2)
            }
            Spacer(minLength: 0)
            if family == .systemMedium {
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(.indigo)
            }
        }
    }
}
