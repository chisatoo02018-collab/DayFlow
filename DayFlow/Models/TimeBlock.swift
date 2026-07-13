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
    /// The primary activity — colors the arc and drives the 内訳 partition.
    var categoryID: String
    /// Secondary categories that overlap this stretch without owning it (e.g. a 移動 block
    /// tagged 運動 for a brisk walk). Never colors the main arc; shown as a thin inner ring
    /// and glyphs. Category ids, same namespace as `categoryID`.
    var tags: [String]
    var start: Int
    var end: Int
    var source: TimeBlockSource
    var isUserModified: Bool

    init(id: UUID = UUID(), categoryID: String, tags: [String] = [], start: Int, end: Int,
         source: TimeBlockSource = .manual, isUserModified: Bool = false) {
        self.id = id
        self.categoryID = categoryID
        self.tags = tags
        self.start = start
        self.end = end
        self.source = source
        self.isUserModified = isUserModified
    }

    var durationMinutes: Int { max(0, end - start) }

    private enum CodingKeys: String, CodingKey {
        case id, categoryID, tags, start, end, source, isUserModified
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        categoryID = try values.decode(String.self, forKey: .categoryID)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
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

    /// Expand blocks' `tags` into a per-slot `Set` array (empty set = no tags).
    static func tagSlots(from blocks: [TimeBlock]) -> [Set<String>] {
        var slots = [Set<String>](repeating: [], count: slotsPerDay)
        for block in blocks where !block.tags.isEmpty {
            let lo = max(0, block.start / slotMinutes)
            let hi = min(slotsPerDay, block.end / slotMinutes)
            guard lo < hi else { continue }
            for i in lo..<hi { slots[i].formUnion(block.tags) }
        }
        return slots
    }

    /// Collapse a slot array back into contiguous same-category blocks.
    static func blocks(from slots: [String?], source: TimeBlockSource = .manual,
                       isUserModified: Bool = false) -> [TimeBlock] {
        blocks(from: slots, tagSlots: [Set<String>](repeating: [], count: slots.count),
               source: source, isUserModified: isUserModified)
    }

    /// Collapse primary + tag slot arrays into blocks. A new block starts whenever the
    /// primary category OR the tag set changes, so tags ride along with the run they cover.
    static func blocks(from slots: [String?], tagSlots: [Set<String>],
                       source: TimeBlockSource = .manual,
                       isUserModified: Bool = false) -> [TimeBlock] {
        var result: [TimeBlock] = []
        var i = 0
        while i < slots.count {
            guard let cat = slots[i] else { i += 1; continue }
            let tags = i < tagSlots.count ? tagSlots[i] : []
            var j = i + 1
            while j < slots.count, slots[j] == cat,
                  (j < tagSlots.count ? tagSlots[j] : []) == tags { j += 1 }
            result.append(TimeBlock(categoryID: cat, tags: tags.sorted(),
                                    start: i * slotMinutes, end: j * slotMinutes,
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
