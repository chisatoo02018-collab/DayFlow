import Foundation
import Observation

/// A single pending whole-file write, persisted so a save made offline survives an app
/// restart and flushes later. Keyed by `path`, so re-queuing the same day just replaces
/// the pending content — the vault only ever sees the latest render.
struct ScheduleSyncOp: Codable, Identifiable {
    let id: UUID
    let path: String
    var content: String
    var message: String
    var dailySnapshot: DailyScheduleSnapshot?
    var healthSnapshot: DailyHealthSnapshot?

    init(path: String, content: String, message: String,
         dailySnapshot: DailyScheduleSnapshot? = nil, healthSnapshot: DailyHealthSnapshot? = nil) {
        self.id = UUID()
        self.path = path
        self.content = content
        self.message = message
        self.dailySnapshot = dailySnapshot
        self.healthSnapshot = healthSnapshot
    }
}

struct DailyScheduleSnapshot: Codable {
    var date: Date
    var plan: DaySchedule
    var actual: DaySchedule
    var categories: [TimeCategory]
}

struct DailyHealthSnapshot: Codable {
    var date: Date
    var snapshot: HealthSnapshot
}

/// Mirrors DayFlow's day-file writes into the GitHub repo via the Contents API, so the
/// canonical vault (and the Mac, which pulls) gets them without opening Obsidian on the
/// phone. Local files remain the app's own source of truth; this is the propagation path.
@Observable
@MainActor
final class GitHubSync {
    var config: GitHubConfig { didSet { persistConfig() } }
    /// User-facing on/off. Mirroring only happens when this is on AND a token exists.
    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) } }
    private(set) var hasToken: Bool
    private(set) var outbox: [ScheduleSyncOp]
    var lastError: String?

    private static let configKey = "githubConfig"
    private static let enabledKey = "githubSyncEnabled"
    private static let outboxKey = "githubOutbox"

    private var isFlushing = false
    private var flushTask: Task<Void, Never>?

    init() {
        config = Self.loadConfig()
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
        hasToken = KeychainStore.get(GitHubClient.tokenAccount)?.isEmpty == false
        outbox = Self.loadOutbox()
    }

    var isActive: Bool { enabled && hasToken && config.isComplete }

    // MARK: - Token

    func setToken(_ token: String?) {
        KeychainStore.set(token, for: GitHubClient.tokenAccount)
        hasToken = (token?.isEmpty == false)
        if hasToken { flush() }
    }

    // MARK: - Enqueue

    /// Queues (or replaces) the pending write for `path`, then kicks a flush. One op per
    /// path — a newer render supersedes an unsent older one.
    func enqueue(path: String, content: String, message: String) {
        outbox.removeAll { $0.path == path }
        outbox.append(ScheduleSyncOp(path: path, content: content, message: message))
        persistOutbox()
        scheduleFlush()
    }

    func enqueueDaily(path: String, date: Date, plan: DaySchedule,
                      actual: DaySchedule, categories: [TimeCategory], message: String) {
        // Preserve any pending health block for the same daily file — they share a path
        // but write to disjoint markers, so one must not evict the other from the outbox.
        let pendingHealth = outbox.first { $0.path == path }?.healthSnapshot
        outbox.removeAll { $0.path == path }
        let snapshot = DailyScheduleSnapshot(date: date, plan: plan, actual: actual, categories: categories)
        outbox.append(ScheduleSyncOp(path: path, content: "", message: message,
                                     dailySnapshot: snapshot, healthSnapshot: pendingHealth))
        persistOutbox()
        scheduleFlush()
    }

    func enqueueDailyHealth(path: String, date: Date, snapshot: HealthSnapshot, message: String) {
        let existing = outbox.first { $0.path == path }
        outbox.removeAll { $0.path == path }
        outbox.append(ScheduleSyncOp(path: path,
                                     content: existing?.content ?? "",
                                     message: message,
                                     dailySnapshot: existing?.dailySnapshot,
                                     healthSnapshot: DailyHealthSnapshot(date: date, snapshot: snapshot)))
        persistOutbox()
        scheduleFlush()
    }

    /// Debounced flush: a burst of saves (e.g. many drag releases while editing a day)
    /// coalesces into a single commit ~2s after the last edit, instead of one commit
    /// per drag. Call `flush()` directly for an immediate attempt (app launch/foreground).
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    // MARK: - Flush

    func flush() {
        guard isActive, !isFlushing, !outbox.isEmpty else { return }
        isFlushing = true
        let client = GitHubClient(config: config,
                                  tokenProvider: { KeychainStore.get(GitHubClient.tokenAccount) })
        let ops = outbox
        Task {
            var remaining = ops
            var failure: String?
            for op in ops {
                do {
                    try await client.mutateFile(path: op.path, message: op.message) { current in
                        // Plain whole-file write when neither section snapshot is present.
                        if op.dailySnapshot == nil, op.healthSnapshot == nil { return op.content }
                        var result: String? = current
                        if let daily = op.dailySnapshot {
                            result = ScheduleMarkdown.upsertDailySection(
                                current: result,
                                date: daily.date,
                                plan: daily.plan,
                                actual: daily.actual,
                                categories: daily.categories
                            )
                        }
                        if let health = op.healthSnapshot {
                            result = ScheduleMarkdown.upsertHealthSection(
                                current: result,
                                date: health.date,
                                snapshot: health.snapshot
                            )
                        }
                        return result ?? op.content
                    }
                    remaining.removeAll { $0.id == op.id }
                } catch {
                    failure = error.localizedDescription
                    break   // stop on first failure; keep it and the rest queued for retry
                }
            }
            self.outbox = remaining
            self.persistOutbox()
            self.lastError = failure
            self.isFlushing = false
        }
    }

    // MARK: - Persistence

    private func persistConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }
    private func persistOutbox() {
        if let data = try? JSONEncoder().encode(outbox) {
            UserDefaults.standard.set(data, forKey: Self.outboxKey)
        }
    }
    private static func loadConfig() -> GitHubConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let cfg = try? JSONDecoder().decode(GitHubConfig.self, from: data)
        else { return .defaultConfig }
        return cfg
    }
    private static func loadOutbox() -> [ScheduleSyncOp] {
        guard let data = UserDefaults.standard.data(forKey: outboxKey),
              let ops = try? JSONDecoder().decode([ScheduleSyncOp].self, from: data)
        else { return [] }
        return ops
    }
}
