import Foundation

/// Renders a day's 予定 + 実績 rings into one Obsidian note, and (for future import)
/// carries the exact block data in a hidden JSON comment so the app can read its own
/// files back without guessing from the tables.
///
/// Path convention: `inputs/timelog/YYYY/MM/YYYY-MM-DD.md`（2026-07-16にルート`TimeLog/`から移動） — a dedicated tree that never
/// clobbers Daily notes, while a `[[YYYY-MM-DD]]` backlink keeps it discoverable.
enum ScheduleMarkdown {
    private static let dailyStart = "<!-- dayflow-daily:start -->"
    private static let dailyEnd = "<!-- dayflow-daily:end -->"
    private static let healthStart = "<!-- dayflow-health:start -->"
    private static let healthEnd = "<!-- dayflow-health:end -->"

    static func vaultPath(for date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        let y = DateFormatting.year.string(from: day)
        let m = DateFormatting.month.string(from: day)
        let key = DateFormatting.dayKey.string(from: day)
        return "inputs/timelog/\(y)/\(m)/\(key).md"
    }

    static func commitMessage(for date: Date) -> String {
        "DayFlow: 時間割 \(DateFormatting.dayKey.string(from: Calendar.current.startOfDay(for: date)))"
    }

    static func dailyPath(for date: Date) -> String {
        let day = Calendar.current.startOfDay(for: date)
        return "daily/\(DateFormatting.year.string(from: day))/\(DateFormatting.month.string(from: day))/\(DateFormatting.dayKey.string(from: day)).md"
    }

    static func dailySkeleton(for date: Date) -> String {
        let key = DateFormatting.dayKey.string(from: Calendar.current.startOfDay(for: date))
        return "# \(key)\n"
    }

    static func upsertDailySection(current: String?, date: Date, plan: DaySchedule,
                                   actual: DaySchedule, categories: [TimeCategory]) -> String {
        var base = current ?? dailySkeleton(for: date)
        let section = dailySection(date: date, plan: plan, actual: actual, categories: categories)
        if let start = base.range(of: dailyStart),
           let end = base.range(of: dailyEnd, range: start.upperBound..<base.endIndex) {
            base.replaceSubrange(start.lowerBound..<end.upperBound, with: section)
            return base
        }
        if !base.hasSuffix("\n") { base += "\n" }
        return base + "\n" + section + "\n"
    }

    /// Upserts the Apple Watch health block in a Daily note, keyed by its own markers so
    /// it never touches the `## DayFlow` schedule block written by `upsertDailySection`.
    static func upsertHealthSection(current: String?, date: Date, snapshot: HealthSnapshot) -> String {
        var base = current ?? dailySkeleton(for: date)
        let section = healthSection(snapshot: snapshot)
        if let start = base.range(of: healthStart),
           let end = base.range(of: healthEnd, range: start.upperBound..<base.endIndex) {
            base.replaceSubrange(start.lowerBound..<end.upperBound, with: section)
            return base
        }
        if !base.hasSuffix("\n") { base += "\n" }
        return base + "\n" + section + "\n"
    }

    static func healthSection(snapshot: HealthSnapshot) -> String {
        var out = "\(healthStart)\n## ヘルス\n\n"
        guard snapshot.hasAnyData else {
            return out + "記録なし\n" + healthEnd
        }
        out += "> [!info] Apple Watch\n"
        func line(_ label: String, _ value: String?) -> String {
            guard let value else { return "" }
            return "> \(label): **\(value)**\n"
        }
        out += line("歩数", snapshot.steps.map { "\($0.formatted()) 歩" })
        out += line("安静時心拍", snapshot.restingHeartRate.map { "\($0) bpm" })
        out += line("平均心拍", snapshot.averageHeartRate.map { "\($0) bpm" })
        out += line("睡眠", snapshot.sleepHours.map { String(format: "%.1f 時間", $0) })
        if let stages = snapshot.sleepStages, stages.hasStages {
            func stage(_ label: String, _ hours: Double?) -> String? {
                guard let hours, hours > 0 else { return nil }
                return String(format: "%@ %.1fh", label, hours)
            }
            let parts = [
                stage("深い", stages.deep),
                stage("浅い", stages.core),
                stage("REM", stages.rem),
                stage("覚醒", stages.awake),
            ].compactMap { $0 }
            out += line("睡眠内訳", parts.isEmpty ? nil : parts.joined(separator: " / "))
        }
        out += line("消費カロリー", snapshot.activeEnergy.map { "\($0) kcal" })
        out += line("運動", snapshot.exerciseMinutes.map { "\($0) 分" })
        out += "\n"
        out += healthEnd
        return out
    }

    static func dailySection(date: Date, plan: DaySchedule, actual: DaySchedule,
                             categories: [TimeCategory]) -> String {
        let key = DateFormatting.dayKey.string(from: Calendar.current.startOfDay(for: date))
        let lookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var out = "\(dailyStart)\n## DayFlow\n\n"
        out += "> [!summary] 時間の記録\n"
        out += "> 予定 **\(hoursText(plan.assignedMinutes))** / 実績 **\(hoursText(actual.assignedMinutes))**\n\n"
        let plotted = actual.blocks.isEmpty ? plan.blocks : actual.blocks
        let label = actual.blocks.isEmpty ? "予定" : "実績"
        if plotted.isEmpty {
            out += "記録なし\n\n"
        } else {
            out += "**\(label)タイムライン**\n\n"
            for block in plotted.sorted(by: { $0.start < $1.start }) {
                let name = lookup[block.categoryID] ?? block.categoryID
                let tagSuffix = block.tags.isEmpty ? "" :
                    " ＋" + block.tags.map { lookup[$0] ?? $0 }.joined(separator: "・")
                out += "- `\(block.start.asClock)–\(block.end.asClock)` \(name)\(tagSuffix)\n"
            }
            out += "\n"
        }
        out += "詳細: [[inputs/timelog/\(DateFormatting.year.string(from: date))/\(DateFormatting.month.string(from: date))/\(key)|時間割を開く]]\n"
        out += dailyEnd
        return out
    }

    /// The full markdown body for `date`, combining both kinds. Empty rings render an
    /// explicit "記録なし" so a file always documents both sections.
    static func render(date: Date, plan: DaySchedule, actual: DaySchedule, categories: [TimeCategory]) -> String {
        let day = Calendar.current.startOfDay(for: date)
        let key = DateFormatting.dayKey.string(from: day)
        let lookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        var out = ""
        out += "---\n"
        out += "date: \(key)\n"
        out += "tags:\n  - dayflow\n  - timelog\n---\n\n"
        out += "# \(key) 時間割\n\n"
        out += "**Daily**: [[\(key)]]\n\n"
        out += section(title: "予定", schedule: plan, lookup: lookup)
        out += "\n"
        out += section(title: "実績", schedule: actual, lookup: lookup)
        out += "\n"
        out += hiddenPayload(date: day, plan: plan, actual: actual, categories: categories)
        out += "\n"
        return out
    }

    private static func section(title: String, schedule: DaySchedule, lookup: [String: TimeCategory]) -> String {
        var out = "## \(title)\n\n"
        let totals = schedule.minutesByCategory
        guard !totals.isEmpty else { return out + "記録なし\n" }

        let dayTotal = max(1, totals.values.reduce(0, +))
        out += "| カテゴリ | 時間 | 割合 |\n| --- | --- | --- |\n"
        for (id, mins) in totals.sorted(by: { $0.value > $1.value }) {
            let name = lookup[id]?.name ?? id
            let pct = Int((Double(mins) / Double(dayTotal) * 100).rounded())
            out += "| \(name) | \(hoursText(mins)) | \(pct)% |\n"
        }
        let assigned = totals.values.reduce(0, +)
        out += "\n記録済み \(hoursText(assigned)) / 未設定 \(hoursText(max(0, 24 * 60 - assigned)))\n"
        return out
    }

    // MARK: - Hidden round-trip payload

    private static let prefix = "<!-- dayflow:"
    private static let suffix = " -->"

    struct Payload: Codable {
        var date: String
        var plan: [TimeBlock]
        var actual: [TimeBlock]
        var categories: [TimeCategory]
    }

    private static func hiddenPayload(date: Date, plan: DaySchedule, actual: DaySchedule, categories: [TimeCategory]) -> String {
        let payload = Payload(date: DateFormatting.dayKey.string(from: date),
                              plan: plan.blocks, actual: actual.blocks,
                              categories: categories.filter(\.isCustom))
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return "\(prefix)\(json)\(suffix)\n"
    }

    /// Parses the hidden payload back out of a note the app wrote earlier (for import).
    static func parsePayload(from markdown: String) -> Payload? {
        guard let start = markdown.range(of: prefix),
              let end = markdown.range(of: suffix, range: start.upperBound..<markdown.endIndex)
        else { return nil }
        let json = String(markdown[start.upperBound..<end.lowerBound])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func hoursText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)分" }
        if m == 0 { return "\(h)時間" }
        return "\(h)時間\(m)分"
    }
}

extension DateFormatting {
    static let year: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy"; return f
    }()
    static let month: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM"; return f
    }()
}
