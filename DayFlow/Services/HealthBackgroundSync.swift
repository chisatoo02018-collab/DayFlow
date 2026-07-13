import HealthKit

/// Keeps the Obsidian daily-note health block current without the user opening the app.
///
/// Registers an `HKObserverQuery` + background delivery for the metrics we mirror. When the
/// Apple Watch syncs new data, iOS relaunches DayFlow in the background and fires the
/// observer; we fetch the day's snapshot, write the `## ヘルス` block via a fresh
/// `VaultWriter` (all sync config is persisted, so a background instance reconstructs it),
/// and push. Ring editing still happens in the foreground — this only keeps the summary
/// and daily note flowing.
@MainActor
final class HealthBackgroundSync {
    static let shared = HealthBackgroundSync()

    private let store = HKHealthStore()
    private let health = HealthService()
    private var observersRegistered = false

    private var deliveryTypes: [HKSampleType] {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.restingHeartRate),
            HKCategoryType(.sleepAnalysis),
        ]
    }

    /// Safe to call on every launch and after authorization — background delivery is
    /// re-enabled idempotently and observers are registered exactly once per process.
    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        for type in deliveryTypes {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }

        guard !observersRegistered else { return }
        observersRegistered = true

        for type in deliveryTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, _ in
                Task { @MainActor in
                    await self?.sync()
                    completionHandler()   // tell HealthKit we're done so it can sleep the app
                }
            }
            store.execute(query)
        }
    }

    /// Fetch today's metrics and mirror the daily-note health block. Best-effort and
    /// idempotent; the whole block is regenerated so repeated runs just refresh it.
    func sync() async {
        await health.refresh()
        guard health.snapshot.hasAnyData else { return }
        let writer = VaultWriter()
        guard writer.isConfigured else { return }
        writer.writeHealth(date: Date(), snapshot: health.snapshot)
        writer.github.flush()
    }
}
