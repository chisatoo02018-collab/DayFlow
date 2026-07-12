import Foundation

/// Whether a day's ring is a *plan* (時間割 — how you intend to spend the day) or an
/// *actual* record (実績 — how you really spent it, typically filled in the next day).
/// Both share the same editor and storage; only the label and default date differ.
enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case plan
    case actual

    var id: String { rawValue }
    var title: String { self == .plan ? "予定" : "実績" }
}

/// One day's ring for one kind. `date` is normalized to the start of the day; the
/// pair (date, kind) is the storage key.
struct DaySchedule: Codable, Equatable {
    var date: Date
    var kind: ScheduleKind
    var blocks: [TimeBlock]

    init(date: Date, kind: ScheduleKind, blocks: [TimeBlock] = []) {
        self.date = Calendar.current.startOfDay(for: date)
        self.kind = kind
        self.blocks = blocks
    }

    /// Total assigned minutes per category id, for the summary breakdown.
    var minutesByCategory: [String: Int] {
        blocks.reduce(into: [:]) { acc, block in
            acc[block.categoryID, default: 0] += block.durationMinutes
        }
    }

    var assignedMinutes: Int { blocks.reduce(0) { $0 + $1.durationMinutes } }

    static func key(date: Date, kind: ScheduleKind) -> String {
        let day = Calendar.current.startOfDay(for: date)
        return "\(DateFormatting.dayKey.string(from: day))_\(kind.rawValue)"
    }
}

enum DateFormatting {
    /// `yyyy-MM-dd`, POSIX/UTC-stable, used for storage keys and vault paths/filenames.
    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
