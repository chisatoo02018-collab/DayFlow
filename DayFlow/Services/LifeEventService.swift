import Foundation
import Observation

/// Reconstructs a day's life events (YouTube views + purchases) from the Obsidian vault.
///
/// DayFlow does not collect this data — it is already ingested into the vault by separate
/// automations (`inputs/閲覧履歴/youtube/…`, `inputs/購入履歴/…`). This service only *reads*
/// those canonical files and parses their markdown tables, mirroring the母艦 principle:
/// collected-elsewhere data is restored and displayed here, never re-collected.
///
/// Read path follows `VaultWriter`'s two propagation channels in reverse: the picked local
/// vault folder (security-scoped) first — offline, no rate limit — then the GitHub mirror.
@Observable
@MainActor
final class LifeEventService {
    var events: [DayEvent] = []
    var isLoading = false
    private var loadedKey: String?

    /// Purchase sources correspond to the subfolders under `inputs/購入履歴/`. Kept as a fixed
    /// list so a single read path works for both local and GitHub (no directory listing needed).
    private static let purchaseSources: [(dir: String, label: String)] = [
        ("amazon", "Amazon"), ("rakuten", "楽天"), ("apple", "Apple"),
        ("paidy", "Paidy"), ("smbc_card", "三井住友カード"), ("smbc_payment", "三井住友"),
        ("google_play", "Google Play"), ("fanza", "FANZA"), ("timescar", "タイムズカー"),
        ("rakuten_mobile", "楽天モバイル"), ("sbi_trade", "SBI"),
    ]

    /// Loads `date`'s events. Idempotent per day unless `force` is set (pull-to-refresh).
    func load(date: Date, vault: VaultWriter, force: Bool = false) async {
        let key = Self.dayKey(date)
        if !force, loadedKey == key { return }
        isLoading = true
        defer { isLoading = false }

        var result = await youtubeEvents(date: date, vault: vault)
        result += await purchaseEvents(date: date, vault: vault)
        // Timed events ascending; day-level (purchases) sink below the timeline.
        result.sort { a, b in
            switch (a.minutes, b.minutes) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }
        events = result
        loadedKey = key
    }

    // MARK: - Parsers

    private func youtubeEvents(date: Date, vault: VaultWriter) async -> [DayEvent] {
        let key = Self.dayKey(date)
        let path = "inputs/閲覧履歴/youtube/takeout/\(key)_youtube.md"
        guard let text = await readFile(path, vault: vault) else { return [] }
        var out: [DayEvent] = []
        for raw in text.split(separator: "\n") {
            let cols = Self.cells(raw)
            guard cols.count >= 4, let minutes = Self.parseClock(cols[1]) else { continue }
            let title = cols[2]
            guard !title.isEmpty else { continue }
            out.append(DayEvent(kind: .youtube, minutes: minutes,
                                title: title, subtitle: cols[3].isEmpty ? nil : cols[3]))
        }
        return out
    }

    private func purchaseEvents(date: Date, vault: VaultWriter) async -> [DayEvent] {
        let dayKey = Self.dayKey(date)
        let monthKey = String(dayKey.prefix(7))   // "YYYY-MM"
        var out: [DayEvent] = []
        for source in Self.purchaseSources {
            let path = "inputs/購入履歴/\(source.dir)/\(monthKey).md"
            guard let text = await readFile(path, vault: vault) else { continue }
            for raw in text.split(separator: "\n") {
                let cols = Self.cells(raw)
                // | 日付 | 種別 | 商品 | 金額 | 注文番号 |
                guard cols.count >= 5, cols[1] == dayKey else { continue }
                out.append(DayEvent(kind: .purchase, minutes: nil,
                                    title: Self.shorten(cols[3]),
                                    subtitle: cols[2].isEmpty ? source.label : "\(source.label)・\(cols[2])",
                                    amountYen: Self.parseYen(cols[4])))
            }
        }
        return out
    }

    // MARK: - Vault read (local bookmark first, then GitHub mirror)

    private func readFile(_ relPath: String, vault: VaultWriter) async -> String? {
        if let base = vault.vaultURL, let text = Self.readLocal(relPath, base: base) {
            return text
        }
        if vault.github.isActive {
            let client = GitHubClient(config: vault.github.config,
                                      tokenProvider: { KeychainStore.get(GitHubClient.tokenAccount) })
            if let state = try? await client.fetchFile(path: relPath) {
                return state.content
            }
        }
        return nil
    }

    private static func readLocal(_ relPath: String, base: URL) -> String? {
        guard base.startAccessingSecurityScopedResource() else { return nil }
        defer { base.stopAccessingSecurityScopedResource() }
        let fileURL = base.appendingPathComponent(relPath)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    // MARK: - Markdown/table helpers

    /// Trimmed cells of a `| a | b | c |` row. Non-table lines yield too few cells and are
    /// filtered by callers. Trailing `<!-- … -->` comment columns are simply ignored by index.
    static func cells(_ line: Substring) -> [String] {
        guard line.hasPrefix("|") else { return [] }
        return line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// "HH:MM" → minutes from midnight. Returns nil for header ("時刻") and separator rows.
    static func parseClock(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// "¥19980" / "¥19,980" / "19980円" → 19980. nil when no digits.
    static func parseYen(_ s: String) -> Int? {
        let digits = s.filter { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Purchase product cells concatenate many items; show the first and note the rest so a
    /// multi-item order reads as one compact line.
    static func shorten(_ s: String, limit: Int = 32) -> String {
        let items = s.split(separator: ",", omittingEmptySubsequences: true)
        var head = (items.first.map(String.init) ?? s).trimmingCharacters(in: .whitespaces)
        if head.count > limit { head = String(head.prefix(limit)) + "…" }
        if items.count > 1 { head += " 他\(items.count - 1)点" }
        return head
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
}
