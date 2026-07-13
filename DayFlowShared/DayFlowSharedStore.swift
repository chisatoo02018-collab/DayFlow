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
        case todayActual
        case wakeTimePicker
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
        mergePlanBlock(day: day, range: range, categoryID: "sleep")
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
