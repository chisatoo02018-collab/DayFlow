import Foundation
import Observation

/// Owns the time-schedule domain: the category list (presets + user's custom ones) and
/// every saved `DaySchedule`, persisted as JSON in the app's Documents directory.
///
/// This is the app's own source of truth. Obsidian mirroring (Phase 2) reads from here;
/// it is not required for the editor to work.
@Observable
final class ScheduleStore {
    /// Presets first, then the user's custom categories (in creation order).
    private(set) var categories: [TimeCategory]
    private(set) var templates: [ScheduleTemplate]

    /// All saved schedules, keyed by `DaySchedule.key(date:kind:)`.
    private var schedules: [String: DaySchedule]

    private let dir: URL
    private let schedulesURL: URL
    private let categoriesURL: URL
    private let templatesURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DayFlowSharedStore.appGroupID
        ) ?? documents
        dir = base
        schedulesURL = base.appendingPathComponent("schedules.json")
        categoriesURL = base.appendingPathComponent("custom_categories.json")
        templatesURL = base.appendingPathComponent("schedule_templates.json")

        Self.migrateLegacyFile(named: "schedules.json", from: documents, to: base)
        Self.migrateLegacyFile(named: "custom_categories.json", from: documents, to: base)
        Self.migrateLegacyFile(named: "schedule_templates.json", from: documents, to: base)

        let custom = Self.load([TimeCategory].self, from: categoriesURL) ?? []
        categories = TimeCategory.presets + custom.filter { $0.isCustom }
        schedules = Self.load([String: DaySchedule].self, from: schedulesURL) ?? [:]
        templates = Self.load([ScheduleTemplate].self, from: templatesURL) ?? []
    }

    // MARK: - Categories

    func category(id: String) -> TimeCategory? {
        categories.first { $0.id == id }
    }

    var customCategories: [TimeCategory] { categories.filter(\.isCustom) }

    /// Adds a custom category. `name` is trimmed; a unique slug id is derived so blocks
    /// and vault markdown stay stable even if the name later changes.
    @discardableResult
    func addCustomCategory(name: String, colorHex: String, symbol: String = "tag.fill") -> TimeCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = uniqueCustomID(base: trimmed)
        let cat = TimeCategory(id: id, name: trimmed.isEmpty ? id : trimmed,
                               colorHex: colorHex, symbol: symbol, isCustom: true)
        categories.append(cat)
        persistCategories()
        return cat
    }

    func updateCustomCategory(_ cat: TimeCategory) {
        guard cat.isCustom, let idx = categories.firstIndex(where: { $0.id == cat.id }) else { return }
        categories[idx] = cat
        persistCategories()
    }

    /// Removes a custom category. Existing blocks that referenced it are left intact but
    /// will render with a fallback style until re-painted, so no schedule data is lost.
    func deleteCustomCategory(id: String) {
        categories.removeAll { $0.id == id && $0.isCustom }
        persistCategories()
    }

    private func uniqueCustomID(base: String) -> String {
        var n = 1
        while true {
            let candidate = "custom-\(n)"
            if !categories.contains(where: { $0.id == candidate }) { return candidate }
            n += 1
        }
    }

    // MARK: - Schedules

    func schedule(date: Date, kind: ScheduleKind) -> DaySchedule {
        schedules[DaySchedule.key(date: date, kind: kind)]
            ?? DaySchedule(date: date, kind: kind)
    }

    func save(_ schedule: DaySchedule) {
        schedules[DaySchedule.key(date: schedule.date, kind: schedule.kind)] = schedule
        persistSchedules()
    }

    func hasSchedule(date: Date, kind: ScheduleKind) -> Bool {
        schedules[DaySchedule.key(date: date, kind: kind)]?.blocks.isEmpty == false
    }

    func copySchedule(date: Date, from source: ScheduleKind, to destination: ScheduleKind) {
        let sourceSchedule = schedule(date: date, kind: source)
        save(DaySchedule(date: date, kind: destination, blocks: sourceSchedule.blocks))
    }

    func schedules(from start: Date, to end: Date, kind: ScheduleKind) -> [DaySchedule] {
        schedules.values
            .filter { $0.kind == kind && $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    /// Reload changes written by a widget, Control Center control, or Shortcut while
    /// the app process was suspended.
    func reloadFromSharedContainer() {
        schedules = Self.load([String: DaySchedule].self, from: schedulesURL) ?? schedules
    }

    @discardableResult
    func saveTemplate(name: String, blocks: [TimeBlock]) -> ScheduleTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = ScheduleTemplate(name: trimmed.isEmpty ? "新しい予定" : trimmed, blocks: blocks)
        templates.append(template)
        persistTemplates()
        return template
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
        persistTemplates()
    }

    // MARK: - Persistence

    private func persistSchedules() { Self.save(schedules, to: schedulesURL) }
    private func persistCategories() { Self.save(customCategories, to: categoriesURL) }
    private func persistTemplates() { Self.save(templates, to: templatesURL) }

    private static func migrateLegacyFile(named name: String, from documents: URL, to base: URL) {
        let oldURL = documents.appendingPathComponent(name)
        let newURL = base.appendingPathComponent(name)
        guard oldURL != newURL,
              !FileManager.default.fileExists(atPath: newURL.path),
              FileManager.default.fileExists(atPath: oldURL.path) else { return }
        try? FileManager.default.copyItem(at: oldURL, to: newURL)
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
