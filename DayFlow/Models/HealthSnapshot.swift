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
    var sleepStages: SleepStages?  // last night's stage breakdown (nil when the source has no stages)
    var activeEnergy: Int?       // activeEnergyBurned, kcal
    var exerciseMinutes: Int?    // appleExerciseTime, minutes

    static let empty = HealthSnapshot()

    var hasAnyData: Bool {
        steps != nil || restingHeartRate != nil || averageHeartRate != nil
            || sleepHours != nil || activeEnergy != nil || exerciseMinutes != nil
    }
}

/// Last night's sleep broken down by HealthKit stage, in hours. Fields are optional so a
/// source that only reports "asleep" (no staging) leaves them `nil`; `hasStages` gates
/// whether the breakdown is worth rendering at all. `awake` is time in bed but awake.
struct SleepStages: Codable, Equatable {
    var deep: Double?    // asleepDeep
    var core: Double?    // asleepCore (light)
    var rem: Double?     // asleepREM
    var awake: Double?   // awake (in bed)

    /// True when at least one distinct stage was measured — i.e. the watch staged the night,
    /// not just logged an undifferentiated asleep block.
    var hasStages: Bool {
        (deep ?? 0) > 0 || (core ?? 0) > 0 || (rem ?? 0) > 0
    }
}
