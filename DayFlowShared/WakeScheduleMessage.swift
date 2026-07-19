import Foundation

/// Property-list-only message contract shared by the iPhone and Apple Watch apps.
/// WatchConnectivity dictionaries must contain values supported by PropertyListSerialization.
enum WakeScheduleMessage {
    enum Kind: String {
        case setWakeTime
        case requestWakeTime
        case wakeTimeState
    }

    private enum Key {
        static let kind = "dayflow.kind"
        static let hour = "dayflow.hour"
        static let minute = "dayflow.minute"
        static let requestID = "dayflow.requestID"
        static let alarmScheduled = "dayflow.alarmScheduled"
        static let message = "dayflow.message"
    }

    static func setWakeTime(hour: Int, minute: Int, requestID: UUID = UUID()) -> [String: Any] {
        [
            Key.kind: Kind.setWakeTime.rawValue,
            Key.hour: hour,
            Key.minute: minute,
            Key.requestID: requestID.uuidString,
        ]
    }

    static func requestWakeTime() -> [String: Any] {
        [Key.kind: Kind.requestWakeTime.rawValue]
    }

    static func wakeTimeState(
        time: Date?,
        alarmScheduled: Bool?,
        message: String? = nil,
        requestID: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [Key.kind: Kind.wakeTimeState.rawValue]
        if let time {
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            payload[Key.hour] = components.hour ?? 7
            payload[Key.minute] = components.minute ?? 0
        }
        if let alarmScheduled { payload[Key.alarmScheduled] = alarmScheduled }
        if let message { payload[Key.message] = message }
        if let requestID { payload[Key.requestID] = requestID }
        return payload
    }

    static func kind(in payload: [String: Any]) -> Kind? {
        guard let rawValue = payload[Key.kind] as? String else { return nil }
        return Kind(rawValue: rawValue)
    }

    static func clockTime(in payload: [String: Any], relativeTo reference: Date = Date()) -> Date? {
        guard let hour = payload[Key.hour] as? Int,
              let minute = payload[Key.minute] as? Int,
              (0..<24).contains(hour),
              (0..<60).contains(minute)
        else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: reference)
    }

    static func requestID(in payload: [String: Any]) -> String? {
        payload[Key.requestID] as? String
    }

    static func alarmWasScheduled(in payload: [String: Any]) -> Bool? {
        payload[Key.alarmScheduled] as? Bool
    }

    static func message(in payload: [String: Any]) -> String? {
        payload[Key.message] as? String
    }
}
