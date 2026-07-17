import SwiftUI

extension Color {
    /// Parses `#RRGGBB` (with or without the leading `#`); falls back to gray on
    /// malformed input so the UI never crashes on bad persisted data.
    ///
    /// Lives in DayFlowShared so both the app and the widget can colour categories from
    /// the same stored hex strings.
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
