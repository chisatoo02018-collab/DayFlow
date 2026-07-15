import Foundation
import Observation

/// A single pending whole-file write, persisted so a save made offline survives an app
/// restart and flushes later. Keyed by `path`, so re-queuing the same day just replaces
/// the pending content — the vault only ever sees the latest render.
struct ScheduleSyncOp: Codable, Identifiable {
    let id: UUID
    let revision: Int64
    let path: String
    var content: String
    var message: String
    var dailySnapshot: DailyScheduleSnapshot?
    var healthSnapshot: DailyHealthSnapshot?

    init(path: String, revision: Int64, content: String, message: String,
         dailySnapshot: DailyScheduleSnapshot? = nil, healthSnapshot: DailyHealthSnapshot? = nil) {
        self.id = UUID()
        self.revision = revision
        self.path = path
        self.content = content
        self.message = message
        self.dailySnapshot = dailySnapshot
        self.healthSnapshot = healthSnapshot
    }

    private enum CodingKeys: String, CodingKey {
        case id, revision, path, content, message, dailySnapshot, healthSnapshot
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        revision = try values.decodeIfPresent(Int64.self, forKey: .revision) ?? 0
        path = try values.decode(String.self, forKey: .path)
        content = try values.decode(String.self, forKey: .content)
        message = try values.decode(String.self, forKey: .message)
        dailySnapshot = try values.decodeIfPresent(DailyScheduleSnapshot.self, forKey: .dailySnapshot)
        healthSnapshot = try values.decodeIfPresent(DailyHealthSnapshot.self, forKey: .healthSnapshot)
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

private struct DayFlowQueuePayload: Codable {
    let id: UUID
    let revision: Int64
    let path: String
    let dailyBlock: String?
    let healthBlock: String?
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
    private var lastRevision: Int64

    init() {
        config = Self.loadConfig()
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
        hasToken = KeychainStore.get(GitHubClient.tokenAccount)?.isEmpty == false
        let loadedOutbox = Self.loadOutbox()
        outbox = loadedOutbox
        lastRevision = loadedOutbox.map(\.revision).max() ?? 0
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
        outbox.append(ScheduleSyncOp(
            path: path, revision: nextRevision(), content: content, message: message
        ))
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
        outbox.append(ScheduleSyncOp(path: path, revision: nextRevision(), content: "", message: message,
                                     dailySnapshot: snapshot, healthSnapshot: pendingHealth))
        persistOutbox()
        scheduleFlush()
    }

    func enqueueDailyHealth(path: String, date: Date, snapshot: HealthSnapshot, message: String) {
        let existing = outbox.first { $0.path == path }
        outbox.removeAll { $0.path == path }
        outbox.append(ScheduleSyncOp(path: path,
                                     revision: nextRevision(),
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
    private func scheduleFlush(after delayNanoseconds: UInt64 = 2_000_000_000) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Wall-clock microseconds plus an in-process monotonic guard. Persisted outbox
    /// revisions seed the guard after relaunch, so newer renders always sort later.
    private func nextRevision() -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1_000_000)
        lastRevision = max(now, lastRevision + 1)
        return lastRevision
    }

    // MARK: - Flush

    func flush() {
        guard isActive, !isFlushing, !outbox.isEmpty else { return }
        isFlushing = true
        let client = GitHubClient(config: config,
                                  tokenProvider: { KeychainStore.get(GitHubClient.tokenAccount) })
        let ops = outbox
        Task {
            var failure: String?
            for op in ops {
                do {
                    if op.dailySnapshot != nil || op.healthSnapshot != nil {
                        try await enqueueDailyMutation(op, using: client)
                    } else {
                        try await client.mutateFile(path: op.path, message: op.message) { _ in op.content }
                    }
                    // Remove only the exact operation that completed. A newer render
                    // may have replaced it in `outbox` while this request was in flight.
                    self.outbox.removeAll { $0.id == op.id }
                    self.persistOutbox()
                } catch {
                    failure = error.localizedDescription
                    break   // stop on first failure; keep it and the rest queued for retry
                }
            }
            self.lastError = failure
            self.isFlushing = false
            // A save made during the request may have scheduled a flush that returned
            // while `isFlushing` was true. Ensure it gets another chance now.
            if !self.outbox.isEmpty {
                self.scheduleFlush(after: failure == nil ? 2_000_000_000 : 15_000_000_000)
            }
        }
    }

    /// Shared Daily notes are written only by the Mac mini. The phone creates one
    /// immutable queue file containing complete marker-delimited blocks.
    private func enqueueDailyMutation(_ op: ScheduleSyncOp, using client: GitHubClient) async throws {
        let dailyBlock = op.dailySnapshot.map {
            ScheduleMarkdown.dailySection(
                date: $0.date, plan: $0.plan, actual: $0.actual, categories: $0.categories
            )
        }
        let healthBlock = op.healthSnapshot.map { ScheduleMarkdown.healthSection(snapshot: $0.snapshot) }
        let payload = DayFlowQueuePayload(
            id: op.id, revision: op.revision, path: op.path,
            dailyBlock: dailyBlock, healthBlock: healthBlock
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else { throw GitHubError.decoding }
        let queuePath = String(
            format: "inputs/system/ingest/dayflow/pending/%020lld-%@.json",
            op.revision, op.id.uuidString
        )
        try await client.putFile(
            path: queuePath,
            content: json + "\n",
            message: "dayflow: queue Daily blocks",
            sha: nil
        )
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
