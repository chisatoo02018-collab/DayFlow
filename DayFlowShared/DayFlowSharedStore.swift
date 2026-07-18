import Foundation

struct WorkdayRecord: Codable, Equatable {
    var date: Date
    var arrivedAt: Date?
    var leftAt: Date?

    var isWorking: Bool { arrivedAt != nil && leftAt == nil }
}

enum WorkLogAction: String, Codable {
    case arrive
    case leave

    var title: String { self == .arrive ? "出社" : "退社" }
    var systemImage: String { self == .arrive ? "building.2.fill" : "figure.walk.departure" }
}

enum DayFlowSharedStore {
    static let appGroupID = "group.com.chisatoo.dayflow"
    private static let workLogsFile = "work_logs.json"
    private static let schedulesFile = "schedules.json"
    private static let pendingRouteKey = "pendingRoute"

    enum Route: String {
        case today
        case todayActual
        case insights
        case wakeTimePicker
    }

    /// One URL contract for every widget and system surface that opens the app.
    /// Keeping this in the shared module means a widget never needs to know about
    /// the app's TabView implementation.
    static func deepLink(for route: Route) -> URL {
        URL(string: "dayflow://open/\(route.rawValue)")!
    }

    static func route(from url: URL) -> Route? {
        guard url.scheme == "dayflow", url.host == "open" else { return nil }
        return Route(rawValue: url.lastPathComponent)
    }

    static func workRecord(on date: Date = Date()) -> WorkdayRecord? {
        loadWorkLogs()[dayKey(date)]
    }

    @discardableResult
    static func record(_ action: WorkLogAction, at date: Date = Date()) throws -> WorkdayRecord {
        var logs = loadWorkLogs()
        let key = dayKey(date)
        var record = logs[key] ?? WorkdayRecord(date: Calendar.current.startOfDay(for: date))

        switch action {
        case .arrive:
            record.arrivedAt = date
            record.leftAt = nil
        case .leave:
            record.leftAt = date
            if let arrivedAt = record.arrivedAt {
                mergeWorkBlock(from: arrivedAt, to: date)
            }
        }

        logs[key] = record
        try save(logs, named: workLogsFile)
        return record
    }

    static func suggestedAction(on date: Date = Date()) -> WorkLogAction {
        workRecord(on: date)?.isWorking == true ? .leave : .arrive
    }

    static func requestRoute(_ route: Route) {
        UserDefaults(suiteName: appGroupID)?.set(route.rawValue, forKey: pendingRouteKey)
    }

    static func consumeRoute() -> Route? {
        let defaults = UserDefaults(suiteName: appGroupID)
        guard let raw = defaults?.string(forKey: pendingRouteKey) else { return nil }
        defaults?.removeObject(forKey: pendingRouteKey)
        return Route(rawValue: raw)
    }

    /// Save one edge of the planned sleep window without overwriting other planned activity.
    static func recordPlannedSleepEdge(time: Date, isWakeTime: Bool, now: Date = Date()) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let minutes = hour * 60 + minute

        let day: Date
        let range: Range<Int>
        if isWakeTime {
            let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
            let occurrence = candidate > now
                ? candidate
                : (calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate)
            day = calendar.startOfDay(for: occurrence)
            range = 0..<max(0, min(1440, minutes))
        } else {
            day = calendar.startOfDay(for: now)
            range = max(0, min(1440, minutes))..<1440
        }
        if isWakeTime {
            replaceMorningSleepBlock(day: day, wakeMinute: minutes)
        } else {
            mergePlanBlock(day: day, range: range, categoryID: "sleep")
        }
    }

    private struct SharedSchedule: Codable {
        var date: Date
        var kind: String
        var blocks: [SharedBlock]
    }

    private struct SharedBlock: Codable {
        var id: UUID
        var categoryID: String
        var tags: [String]
        var start: Int
        var end: Int
        var source: String
        var isUserModified: Bool
    }

    /// Fill only unassigned time, preserving deliberate manual/HealthKit edits.
    private static func mergeWorkBlock(from startDate: Date, to endDate: Date) {
        guard endDate > startDate else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: startDate)
        guard calendar.isDate(endDate, inSameDayAs: day) else { return }

        var schedules: [String: SharedSchedule] = load(named: schedulesFile) ?? [:]
        let key = "\(dayKey(day))_actual"
        var schedule = schedules[key] ?? SharedSchedule(date: day, kind: "actual", blocks: [])
        var slots = [SharedBlock?](repeating: nil, count: 288)
        for block in schedule.blocks {
            let lower = max(0, block.start / 5)
            let upper = min(288, Int(ceil(Double(block.end) / 5.0)))
            guard lower < upper else { continue }
            for index in lower..<upper { slots[index] = block }
        }

        let startMinute = calendar.dateComponents([.minute], from: day, to: startDate).minute ?? 0
        let endMinute = calendar.dateComponents([.minute], from: day, to: endDate).minute ?? 0
        let lower = max(0, startMinute / 5)
        let upper = min(288, Int(ceil(Double(endMinute) / 5.0)))
        guard lower < upper else { return }
        let work = SharedBlock(id: UUID(), categoryID: "work", tags: [], start: lower * 5,
                               end: upper * 5, source: "imported", isUserModified: false)
        for index in lower..<upper where slots[index] == nil { slots[index] = work }

        var blocks: [SharedBlock] = []
        var index = 0
        while index < slots.count {
            guard let slot = slots[index] else { index += 1; continue }
            var end = index + 1
            while end < slots.count,
                  slots[end]?.categoryID == slot.categoryID,
                  slots[end]?.tags == slot.tags,
                  slots[end]?.source == slot.source,
                  slots[end]?.isUserModified == slot.isUserModified { end += 1 }
            blocks.append(SharedBlock(id: UUID(), categoryID: slot.categoryID, tags: slot.tags,
                                      start: index * 5, end: end * 5, source: slot.source,
                                      isUserModified: slot.isUserModified))
            index = end
        }
        schedule.blocks = blocks
        schedules[key] = schedule
        try? save(schedules, named: schedulesFile)
    }

    private static func mergePlanBlock(day: Date, range: Range<Int>, categoryID: String) {
        guard !range.isEmpty else { return }
        var schedules: [String: SharedSchedule] = load(named: schedulesFile) ?? [:]
        let key = "\(dayKey(day))_plan"
        var schedule = schedules[key] ?? SharedSchedule(date: Calendar.current.startOfDay(for: day), kind: "plan", blocks: [])
        var slots = [SharedBlock?](repeating: nil, count: 288)
        for block in schedule.blocks {
            let lower = max(0, block.start / 5)
            let upper = min(288, Int(ceil(Double(block.end) / 5.0)))
            guard lower < upper else { continue }
            for index in lower..<upper { slots[index] = block }
        }
        let lower = max(0, range.lowerBound / 5)
        let upper = min(288, Int(ceil(Double(range.upperBound) / 5.0)))
        let planned = SharedBlock(id: UUID(), categoryID: categoryID, tags: [], start: lower * 5,
                                  end: upper * 5, source: "imported", isUserModified: false)
        for index in lower..<upper where slots[index] == nil { slots[index] = planned }

        var blocks: [SharedBlock] = []
        var index = 0
        while index < slots.count {
            guard let slot = slots[index] else { index += 1; continue }
            var end = index + 1
            while end < slots.count,
                  slots[end]?.categoryID == slot.categoryID,
                  slots[end]?.tags == slot.tags,
                  slots[end]?.source == slot.source,
                  slots[end]?.isUserModified == slot.isUserModified { end += 1 }
            blocks.append(SharedBlock(id: UUID(), categoryID: slot.categoryID, tags: slot.tags,
                                      start: index * 5, end: end * 5, source: slot.source,
                                      isUserModified: slot.isUserModified))
            index = end
        }
        schedule.blocks = blocks
        schedules[key] = schedule
        try? save(schedules, named: schedulesFile)
    }

    /// Replace the sleep segment connected to midnight while preserving daytime
    /// activities and the separate bedtime segment later on the same date.
    private static func replaceMorningSleepBlock(day: Date, wakeMinute: Int) {
        var schedules: [String: SharedSchedule] = load(named: schedulesFile) ?? [:]
        let key = "\(dayKey(day))_plan"
        var schedule = schedules[key] ?? SharedSchedule(
            date: Calendar.current.startOfDay(for: day), kind: "plan", blocks: []
        )
        var slots = [SharedBlock?](repeating: nil, count: 288)
        for block in schedule.blocks {
            let lower = max(0, block.start / 5)
            let upper = min(288, Int(ceil(Double(block.end) / 5.0)))
            guard lower < upper else { continue }
            for index in lower..<upper { slots[index] = block }
        }

        // Remove only the leading sleep run that represents the old wake time.
        var index = 0
        while index < slots.count, slots[index]?.categoryID == "sleep" {
            slots[index] = nil
            index += 1
        }

        let upper = min(288, Int(ceil(Double(max(0, min(1440, wakeMinute))) / 5.0)))
        let sleep = SharedBlock(id: UUID(), categoryID: "sleep", tags: [], start: 0,
                                end: upper * 5, source: "imported", isUserModified: false)
        for slot in 0..<upper where slots[slot] == nil { slots[slot] = sleep }

        schedule.blocks = compactBlocks(from: slots)
        schedules[key] = schedule
        try? save(schedules, named: schedulesFile)
    }

    private static func compactBlocks(from slots: [SharedBlock?]) -> [SharedBlock] {
        var blocks: [SharedBlock] = []
        var index = 0
        while index < slots.count {
            guard let slot = slots[index] else { index += 1; continue }
            var end = index + 1
            while end < slots.count,
                  slots[end]?.categoryID == slot.categoryID,
                  slots[end]?.tags == slot.tags,
                  slots[end]?.source == slot.source,
                  slots[end]?.isUserModified == slot.isUserModified { end += 1 }
            blocks.append(SharedBlock(id: UUID(), categoryID: slot.categoryID, tags: slot.tags,
                                      start: index * 5, end: end * 5, source: slot.source,
                                      isUserModified: slot.isUserModified))
            index = end
        }
        return blocks
    }

    // MARK: - Typical day (widget summary)

    /// One category's share of a typical day, averaged over the days that actually have a
    /// recorded 実績.
    struct CategoryAverage: Identifiable, Equatable {
        var id: String
        var name: String
        var colorHex: String
        var averageMinutes: Int
    }

    struct TypicalDay: Equatable {
        var averages: [CategoryAverage]   // sorted, longest first
        var daysWithData: Int
        var officeDays: Int               // days a 仕事 block was recorded
    }

    /// Preset category id → (name, colour). Stable slugs, mirrored from `TimeCategory.presets`
    /// so the widget (which can't see the app's models) can label the ring.
    private static let presetCategories: [String: (String, String)] = [
        "sleep": ("睡眠", "#4C6EF5"), "work": ("仕事", "#FA5252"),
        "study": ("学習", "#7950F2"), "meal": ("食事", "#FD7E14"),
        "commute": ("移動", "#22B8CF"), "exercise": ("運動", "#40C057"),
        "chores": ("家事", "#94D82D"), "leisure": ("娯楽", "#F783AC"),
        "free": ("自由", "#ADB5BD"),
    ]

    private struct SharedCategory: Codable { var id: String; var name: String; var colorHex: String }

    /// Averages the recorded 実績 over the last `days` days into a "typical day" breakdown.
    /// Only days that carry any blocks count toward the average, so a week with 3 recorded
    /// days divides by 3, not 7.
    static func typicalDay(days: Int = 30) -> TypicalDay {
        let schedules: [String: SharedSchedule] = load(named: schedulesFile) ?? [:]
        let customList: [SharedCategory] = load(named: "custom_categories.json") ?? []
        var nameColor = presetCategories
        for c in customList { nameColor[c.id] = (c.name, c.colorHex) }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var totals: [String: Int] = [:]
        var daysWithData = 0
        var officeDays = 0

        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = "\(dayKey(day))_actual"
            guard let sched = schedules[key], !sched.blocks.isEmpty else { continue }
            daysWithData += 1
            var sawOffice = false
            for block in sched.blocks {
                let minutes = max(0, block.end - block.start)
                totals[block.categoryID, default: 0] += minutes
                if block.categoryID == "work" { sawOffice = true }
            }
            if sawOffice { officeDays += 1 }
        }

        guard daysWithData > 0 else {
            return TypicalDay(averages: [], daysWithData: 0, officeDays: 0)
        }

        let averages = totals.map { id, total -> CategoryAverage in
            let meta = nameColor[id] ?? (id, "#ADB5BD")
            return CategoryAverage(id: id, name: meta.0, colorHex: meta.1,
                                   averageMinutes: Int((Double(total) / Double(daysWithData)).rounded()))
        }
        .filter { $0.averageMinutes > 0 }
        .sorted { $0.averageMinutes > $1.averageMinutes }

        return TypicalDay(averages: averages, daysWithData: daysWithData, officeDays: officeDays)
    }

    private static func loadWorkLogs() -> [String: WorkdayRecord] {
        load(named: workLogsFile) ?? [:]
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func url(named name: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(name)
    }

    private static func load<T: Decodable>(named name: String) -> T? {
        guard let url = url(named: name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, named name: String) throws {
        guard let url = url(named: name) else { throw CocoaError(.fileNoSuchFile) }
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }
}
