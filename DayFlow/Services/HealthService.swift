import HealthKit
import SwiftUI

/// Reads today's health metrics from HealthKit, mirroring the `@Observable` +
/// `requestAccess()` / `refresh()` shape of `CalendarService`. Read-only: DayFlow
/// never writes back to HealthKit, so only `read` types are requested.
///
/// HealthKit deliberately hides read-authorization status for privacy, so we don't
/// try to inspect it — we request once, then fetch. Missing data simply comes back
/// as `nil` and renders as a dash.
@Observable
final class HealthService {
    private let store = HKHealthStore()
    private let hrUnit = HKUnit.count().unitDivided(by: .minute())

    let isAvailable = HKHealthStore.isHealthDataAvailable()
    var snapshot = HealthSnapshot.empty

    private static let sleepImportKey = "sleepAutoImportFromHealth"
    private static let exerciseImportKey = "exerciseAutoImportFromHealth"

    /// When on, the 実績 ring treats HealthKit sleep as the source of truth for the
    /// 睡眠 category and auto-fills it on view. Persisted across launches.
    var importsSleepToRing: Bool = UserDefaults.standard.bool(forKey: sleepImportKey) {
        didSet { UserDefaults.standard.set(importsSleepToRing, forKey: Self.sleepImportKey) }
    }

    /// When on, HealthKit exercise minutes seed the 運動 category on the 実績 ring —
    /// filling unaccounted active time, or riding as a tag over another activity.
    var importsExerciseToRing: Bool = UserDefaults.standard.bool(forKey: exerciseImportKey) {
        didSet { UserDefaults.standard.set(importsExerciseToRing, forKey: Self.exerciseImportKey) }
    }

    private static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKCategoryType(.sleepAnalysis),
        ]
    }

    func requestAccess() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            await refresh()
        } catch {
            // Authorization sheet dismissed or unavailable — leave snapshot empty.
        }
    }

    func refresh() async {
        guard isAvailable else { return }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let now = Date()
        // Last night's sleep: from 6pm the previous evening up to now.
        let sleepStart = calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay

        async let steps = sum(.stepCount, unit: .count(), from: startOfDay, to: now)
        async let energy = sum(.activeEnergyBurned, unit: .kilocalorie(), from: startOfDay, to: now)
        async let exercise = sum(.appleExerciseTime, unit: .minute(), from: startOfDay, to: now)
        async let resting = average(.restingHeartRate, unit: hrUnit, from: startOfDay, to: now)
        async let avgHR = average(.heartRate, unit: hrUnit, from: startOfDay, to: now)
        async let sleep = sleepHours(from: sleepStart, to: now)
        async let stages = sleepStages(from: sleepStart, to: now)

        var snap = HealthSnapshot()
        snap.steps = await steps.map { Int($0) }
        snap.activeEnergy = await energy.map { Int($0) }
        snap.exerciseMinutes = await exercise.map { Int($0) }
        snap.restingHeartRate = await resting.map { Int($0.rounded()) }
        snap.averageHeartRate = await avgHR.map { Int($0.rounded()) }
        snap.sleepHours = await sleep
        snap.sleepStages = await stages

        let result = snap
        await MainActor.run { snapshot = result }
    }

    // MARK: - Query helpers

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func sleepHours(from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                // Merge before summing: overlapping asleep samples (multiple sources, or a
                // summary sample over stage samples) would otherwise double-count the hours.
                let asleep = samples
                    .filter { Self.asleepValues.contains($0.value) }
                    .map { DateInterval(start: $0.startDate, end: $0.endDate) }
                let seconds = Self.merged(asleep).reduce(0.0) { $0 + $1.duration }
                continuation.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }

    /// Last night's sleep split by stage, in hours. Each stage is merged independently before
    /// summing, so overlapping samples from multiple sources don't double-count. Returns `nil`
    /// when no sleep samples exist at all; a source that only logs undifferentiated "asleep"
    /// yields a `SleepStages` whose stage fields are `nil`/zero (`hasStages == false`).
    private func sleepStages(from start: Date, to end: Date) async -> SleepStages? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                func hours(_ value: HKCategoryValueSleepAnalysis) -> Double? {
                    let intervals = samples
                        .filter { $0.value == value.rawValue }
                        .map { DateInterval(start: $0.startDate, end: $0.endDate) }
                    guard !intervals.isEmpty else { return nil }
                    let seconds = Self.merged(intervals).reduce(0.0) { $0 + $1.duration }
                    return seconds > 0 ? seconds / 3600 : nil
                }
                let stages = SleepStages(
                    deep: hours(.asleepDeep),
                    core: hours(.asleepCore),
                    rem: hours(.asleepREM),
                    awake: hours(.awake)
                )
                continuation.resume(returning: stages)
            }
            store.execute(query)
        }
    }

    /// Union of overlapping/adjacent intervals, sorted by start. Prevents double-counting
    /// when several HealthKit sources cover the same period.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if var last = result.last, interval.start <= last.end {
                if interval.end > last.end {
                    last.end = interval.end
                    result[result.count - 1] = last
                }
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// The asleep stretches that fall inside `date`'s 00:00–24:00 window, clamped to that
    /// window (an overnight sample is split by the day boundary). Used to paint the 睡眠
    /// category onto that day's 実績 ring. Empty when nothing was recorded.
    func sleepIntervals(for date: Date) async -> [DateInterval] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let intervals = samples
                    .filter { Self.asleepValues.contains($0.value) }
                    .map { DateInterval(start: max($0.startDate, dayStart), end: min($0.endDate, dayEnd)) }
                    .filter { $0.duration > 0 }
                continuation.resume(returning: Self.merged(intervals))
            }
            store.execute(query)
        }
    }

    /// Stretches of `date` that logged Apple Exercise minutes (brisk activity), clamped to
    /// the day. Used to seed the 運動 category / tag on the 実績 ring. A walking commute
    /// shows up here even without a formal workout.
    func exerciseIntervals(for date: Date) async -> [DateInterval] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.appleExerciseTime),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let intervals = samples
                    .filter { $0.quantity.doubleValue(for: .minute()) > 0 }
                    .map { DateInterval(start: max($0.startDate, dayStart), end: min($0.endDate, dayEnd)) }
                    .filter { $0.duration > 0 }
                continuation.resume(returning: Self.merged(intervals))
            }
            store.execute(query)
        }
    }
}
