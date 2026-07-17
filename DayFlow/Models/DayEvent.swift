import Foundation

/// A single life event reconstructed from the vault for a given day. The two kinds DayFlow
/// currently ingests differ in time granularity: YouTube views carry a clock time, purchases
/// are day-level (the source records only the order date). `minutes == nil` means day-level.
struct DayEvent: Identifiable {
    let id = UUID()
    var kind: Kind
    var minutes: Int?      // minutes from midnight; nil = day-level (no clock time)
    var title: String
    var subtitle: String?  // channel (YouTube) or "source・種別" (purchase)
    var amountYen: Int?    // purchases only

    enum Kind {
        case youtube
        case purchase
    }

    /// "HH:MM" for timed events, nil for day-level ones.
    var clock: String? {
        guard let minutes else { return nil }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
