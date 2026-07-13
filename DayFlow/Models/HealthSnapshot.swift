import Foundation

/// A day's health metrics read from HealthKit (Apple Watch as the source).
/// Every field is optional: a `nil` means "no data / not authorized" and is
/// rendered as a dash rather than a zero, so an unworn watch never looks like
/// a real zero.
struct HealthSnapshot: Codable, Equatable {
    var steps: Int?              // stepCount, sum over today
    var restingHeartRate: Int?   // restingHeartRate, bpm
    var averageHeartRate: Int?   // heartRate, discrete average over today, bpm
    var sleepHours: Double?      // asleep duration last night, hours
    var activeEnergy: Int?       // activeEnergyBurned, kcal
    var exerciseMinutes: Int?    // appleExerciseTime, minutes

    static let empty = HealthSnapshot()

    var hasAnyData: Bool {
        steps != nil || restingHeartRate != nil || averageHeartRate != nil
            || sleepHours != nil || activeEnergy != nil || exerciseMinutes != nil
    }
}
