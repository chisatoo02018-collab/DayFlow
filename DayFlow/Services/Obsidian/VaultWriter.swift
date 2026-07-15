import Foundation
import Observation

/// Writes a day's time-log into the Obsidian vault. Two propagation paths, mirroring
/// VoiceDrop: the picked local vault folder (security-scoped bookmark) is written
/// directly, and the same content is queued into `GitHubSync` so the canonical repo —
/// and the Mac that pulls it — receives it without opening Obsidian on the phone.
///
/// Everything here is optional: the 時間割 editor works fully without a vault or token;
/// this only runs when the user has configured sync in Settings.
@Observable
@MainActor
final class VaultWriter {
    var vaultURL: URL?
    let github = GitHubSync()

    private static let bookmarkKey = "obsidianVaultBookmark"

    var isConfigured: Bool { vaultURL != nil || github.isActive }

    init() {
        restoreBookmark()
        github.flush()  // drain anything queued while offline last session
    }

    // MARK: - Vault selection

    func selectVault(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? url.bookmarkData(options: .minimalBookmark,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        vaultURL = url
    }

    func resetVault() {
        vaultURL = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [],
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            vaultURL = url
        }
    }

    // MARK: - Write

    /// Renders `date`'s plan + actual and propagates them. Safe to call on every save;
    /// the whole day file is regenerated each time so sections stay consistent.
    func writeDay(date: Date, plan: DaySchedule, actual: DaySchedule, categories: [TimeCategory]) {
        let markdown = ScheduleMarkdown.render(date: date, plan: plan, actual: actual, categories: categories)
        let relPath = ScheduleMarkdown.vaultPath(for: date)
        let dailyPath = ScheduleMarkdown.dailyPath(for: date)

        writeLocal(relPath: relPath, content: markdown)
        // When GitHub propagation is enabled, the Mac mini is the sole shared-Daily
        // writer. Keep only the dedicated TimeLog local mirror on the phone.
        if !github.enabled {
            upsertLocalDaily(
                relPath: dailyPath, date: date, plan: plan,
                actual: actual, categories: categories
            )
        }

        if github.enabled {
            github.enqueue(path: relPath, content: markdown,
                           message: ScheduleMarkdown.commitMessage(for: date))
            github.enqueueDaily(
                path: dailyPath,
                date: date,
                plan: plan,
                actual: actual,
                categories: categories,
                message: "DayFlow: Dailyへ時間記録を反映"
            )
        }
    }

    /// Writes today's Apple Watch metrics into the Daily note's health block. Independent
    /// of `writeDay` — driven by the dashboard's HealthKit refresh — but lands in the same
    /// Daily file via disjoint markers. No-op when nothing is configured.
    func writeHealth(date: Date, snapshot: HealthSnapshot) {
        let dailyPath = ScheduleMarkdown.dailyPath(for: date)
        if !github.enabled {
            upsertLocalDailyHealth(relPath: dailyPath, date: date, snapshot: snapshot)
        }

        if github.enabled {
            github.enqueueDailyHealth(
                path: dailyPath,
                date: date,
                snapshot: snapshot,
                message: "DayFlow: Dailyへ健康データを反映"
            )
        }
    }

    private func upsertLocalDailyHealth(relPath: String, date: Date, snapshot: HealthSnapshot) {
        guard let vaultURL else { return }
        guard vaultURL.startAccessingSecurityScopedResource() else { return }
        defer { vaultURL.stopAccessingSecurityScopedResource() }

        let fileURL = vaultURL.appendingPathComponent(relPath)
        let current = try? String(contentsOf: fileURL, encoding: .utf8)
        let updated = ScheduleMarkdown.upsertHealthSection(current: current, date: date, snapshot: snapshot)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? updated.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    private func writeLocal(relPath: String, content: String) {
        guard let vaultURL else { return }
        guard vaultURL.startAccessingSecurityScopedResource() else { return }
        defer { vaultURL.stopAccessingSecurityScopedResource() }

        let fileURL = vaultURL.appendingPathComponent(relPath)
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    private func upsertLocalDaily(relPath: String, date: Date, plan: DaySchedule,
                                  actual: DaySchedule, categories: [TimeCategory]) {
        guard let vaultURL else { return }
        guard vaultURL.startAccessingSecurityScopedResource() else { return }
        defer { vaultURL.stopAccessingSecurityScopedResource() }

        let fileURL = vaultURL.appendingPathComponent(relPath)
        let current = try? String(contentsOf: fileURL, encoding: .utf8)
        let updated = ScheduleMarkdown.upsertDailySection(
            current: current, date: date, plan: plan, actual: actual, categories: categories
        )
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? updated.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }
}
