import SwiftUI

/// A labelled, colored kind of activity a stretch of the day can be assigned to
/// (睡眠 / 仕事 / 食事 …). Presets ship with the app; users may add custom ones.
///
/// `id` is a stable slug used as the key inside `TimeBlock.categoryID` and in the
/// Obsidian markdown, so it must never change once a block references it — renaming
/// only touches `name`.
struct TimeCategory: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var colorHex: String
    var symbol: String
    var isCustom: Bool

    var color: Color { Color(hex: colorHex) }

    init(id: String, name: String, colorHex: String, symbol: String, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.isCustom = isCustom
    }
}

extension TimeCategory {
    /// Preset categories, ordered for the chip strip. Chosen to cover a typical day
    /// with visually distinct hues (roughly around the color wheel) so adjacent arcs
    /// on the ring stay readable.
    static let presets: [TimeCategory] = [
        TimeCategory(id: "sleep",    name: "睡眠", colorHex: "#4C6EF5", symbol: "moon.fill"),
        TimeCategory(id: "work",     name: "仕事", colorHex: "#FA5252", symbol: "briefcase.fill"),
        TimeCategory(id: "study",    name: "学習", colorHex: "#7950F2", symbol: "book.fill"),
        TimeCategory(id: "meal",     name: "食事", colorHex: "#FD7E14", symbol: "fork.knife"),
        TimeCategory(id: "commute",  name: "移動", colorHex: "#22B8CF", symbol: "tram.fill"),
        TimeCategory(id: "exercise", name: "運動", colorHex: "#40C057", symbol: "figure.run"),
        TimeCategory(id: "chores",   name: "家事", colorHex: "#94D82D", symbol: "house.fill"),
        TimeCategory(id: "leisure",  name: "娯楽", colorHex: "#F783AC", symbol: "gamecontroller.fill"),
        TimeCategory(id: "free",     name: "自由", colorHex: "#ADB5BD", symbol: "sparkles"),
    ]

    /// Palette offered when creating a custom category, kept distinct from — but
    /// harmonious with — the preset hues.
    static let customPalette: [String] = [
        "#E64980", "#BE4BDB", "#7048E8", "#4263EB", "#1C7ED6",
        "#0CA678", "#66A80F", "#F08C00", "#E8590C", "#868E96",
    ]
}

// MARK: - Color <-> hex

extension Color {
    /// Parses `#RRGGBB` (with or without the leading `#`); falls back to gray on
    /// malformed input so the UI never crashes on bad persisted data.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
