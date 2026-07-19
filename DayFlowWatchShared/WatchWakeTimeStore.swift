import Foundation

enum WatchWakeTimeStore {
    static let appGroupID = "group.com.chisatoo.dayflow"
    static let complicationKind = "com.chisatoo.dayflow.watch.wake-time"

    private static let hourKey = "watchWakeHour"
    private static let minuteKey = "watchWakeMinute"
    private static let pendingEditorKey = "pendingWatchWakeTimeEditor"

    static func time(relativeTo reference: Date = Date()) -> Date {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        let hour = defaults.object(forKey: hourKey) as? Int ?? 7
        let minute = defaults.object(forKey: minuteKey) as? Int ?? 0
        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: reference
        ) ?? reference
    }

    static func save(_ time: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        defaults.set(components.hour ?? 7, forKey: hourKey)
        defaults.set(components.minute ?? 0, forKey: minuteKey)
    }

    static func requestEditor() {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        defaults.set(true, forKey: pendingEditorKey)
    }

    static func consumeEditorRequest() -> Bool {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        guard defaults.bool(forKey: pendingEditorKey) else { return false }
        defaults.removeObject(forKey: pendingEditorKey)
        return true
    }
}
