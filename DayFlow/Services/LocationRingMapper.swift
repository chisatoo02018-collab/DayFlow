import Foundation
import SwiftUI

/// Turns location segments into (a) colours for the 所在地 ring and (b) conservative
/// fills for the activity ring.
///
/// The split matters. The 所在地 ring shows *everything* we observed — it's a sensor
/// record. The activity ring is the user's own accounting, so we only add what a
/// location can unambiguously mean, and only where the user left the slot empty:
///
/// - 職場にいた → 仕事 (unambiguous enough to be worth the guess)
/// - 自宅↔職場を移動していた → 移動
/// - 自宅にいた → **nothing**. Home could be 睡眠 / 家事 / 娯楽 / 仕事(在宅) — painting it
///   would be inventing data, which is exactly what the ring is supposed to avoid.
enum LocationRingMapper {
    /// Category ids from `TimeCategory.presets` that a location can imply.
    static let officeCategoryID = "work"
    static let movingCategoryID = "commute"

    /// Per-slot colours for the 所在地 ring (nil = nothing observed).
    static func locationSlots(from segments: [LocationSegment]) -> [Color?] {
        var slots = [Color?](repeating: nil, count: slotsPerDay)
        for seg in segments {
            let color: Color
            switch seg.kind {
            case .stay(_, let placeKind): color = placeKind.color
            case .moving: color = Color(hex: "#22B8CF")   // 移動カテゴリと同系
            case .away: color = Color(hex: "#CED4DA")
            }
            fill(&slots, seg, with: color)
        }
        return slots
    }

    /// Fills *empty* activity slots with what the location unambiguously implies.
    /// Returns a new slot array; slots the user already painted are untouched.
    static func applyToActivitySlots(_ slots: [String?], segments: [LocationSegment]) -> [String?] {
        var result = slots
        for seg in segments {
            let categoryID: String?
            switch seg.kind {
            case .stay(_, let placeKind):
                categoryID = placeKind == .office ? officeCategoryID : nil
            case .moving:
                categoryID = movingCategoryID
            case .away:
                categoryID = nil
            }
            guard let categoryID else { continue }
            let lo = max(0, seg.start / slotMinutes)
            let hi = min(slotsPerDay, seg.end / slotMinutes)
            guard lo < hi else { continue }
            for i in lo..<hi where result[i] == nil {
                result[i] = categoryID
            }
        }
        return result
    }

    /// True when applying the segments would actually change anything — lets the caller
    /// skip a pointless commit (and the vault write / GitHub push behind it).
    static func wouldChange(_ slots: [String?], segments: [LocationSegment]) -> Bool {
        applyToActivitySlots(slots, segments: segments) != slots
    }

    private static func fill(_ slots: inout [Color?], _ seg: LocationSegment, with color: Color) {
        let lo = max(0, seg.start / slotMinutes)
        let hi = min(slotsPerDay, seg.end / slotMinutes)
        guard lo < hi else { return }
        for i in lo..<hi { slots[i] = color }
    }
}
