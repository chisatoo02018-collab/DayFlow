import Foundation

enum TimeBlockSource: String, Codable {
    case manual
    case calendar
    case healthKit
    case imported
}

/// A contiguous run of the day assigned to one category, in minutes-from-midnight.
/// `start ..< end`, both in `0...1440`, never wrapping past midnight — an activity
/// that crosses midnight is stored as two blocks (evening + next morning).
struct TimeBlock: Identifiable, Codable, Equatable {
    var id: UUID
    var categoryID: String
    var start: Int
    var end: Int
    var source: TimeBlockSource
    var isUserModified: Bool

    init(id: UUID = UUID(), categoryID: String, start: Int, end: Int,
         source: TimeBlockSource = .manual, isUserModified: Bool = false) {
        self.id = id
        self.categoryID = categoryID
        self.start = start
        self.end = end
        self.source = source
        self.isUserModified = isUserModified
    }

    var durationMinutes: Int { max(0, end - start) }

    private enum CodingKeys: String, CodingKey {
        case id, categoryID, start, end, source, isUserModified
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        categoryID = try values.decode(String.self, forKey: .categoryID)
        start = try values.decode(Int.self, forKey: .start)
        end = try values.decode(Int.self, forKey: .end)
        source = try values.decodeIfPresent(TimeBlockSource.self, forKey: .source) ?? .manual
        isUserModified = try values.decodeIfPresent(Bool.self, forKey: .isUserModified) ?? false
    }
}

/// How many minutes each editable slot spans. The wheel edits at this resolution and
/// snaps drags to it; blocks are runs of same-category slots. 5 min = 288 slots/day —
/// fine-grained enough to feel continuous, cheap enough to repaint every drag frame.
let slotMinutes = 5
let slotsPerDay = (24 * 60) / slotMinutes   // 288

enum TimeGrid {
    /// Expand blocks into a `[categoryID?]` slot array (nil = unassigned) for painting.
    static func slots(from blocks: [TimeBlock]) -> [String?] {
        var slots = [String?](repeating: nil, count: slotsPerDay)
        for block in blocks {
            let lo = max(0, block.start / slotMinutes)
            let hi = min(slotsPerDay, block.end / slotMinutes)
            guard lo < hi else { continue }
            for i in lo..<hi { slots[i] = block.categoryID }
        }
        return slots
    }

    /// Collapse a slot array back into contiguous same-category blocks.
    static func blocks(from slots: [String?], source: TimeBlockSource = .manual,
                       isUserModified: Bool = false) -> [TimeBlock] {
        var result: [TimeBlock] = []
        var i = 0
        while i < slots.count {
            guard let cat = slots[i] else { i += 1; continue }
            var j = i + 1
            while j < slots.count, slots[j] == cat { j += 1 }
            result.append(TimeBlock(categoryID: cat, start: i * slotMinutes, end: j * slotMinutes,
                                    source: source, isUserModified: isUserModified))
            i = j
        }
        return result
    }
}

extension Int {
    /// Minutes-from-midnight → `"H:mm"` (24h). 1440 renders as `24:00`.
    var asClock: String {
        let h = self / 60
        let m = self % 60
        return String(format: "%d:%02d", h, m)
    }
}
