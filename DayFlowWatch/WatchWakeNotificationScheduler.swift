import Foundation
import UserNotifications

enum WatchWakeNotificationScheduler {
    static let requestIdentifier = "com.chisatoo.dayflow.watch.wake"

    static func schedule(for time: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { return false }

            let next = nextOccurrence(of: time)
            let content = UNMutableNotificationContent()
            content.title = "起床予定"
            content.body = "おはようございます。DayFlowの起床時刻です。"
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: next
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: requestIdentifier,
                content: content,
                trigger: trigger
            )

            center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private static func nextOccurrence(of time: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let today = calendar.date(
            bySettingHour: components.hour ?? 7,
            minute: components.minute ?? 0,
            second: 0,
            of: Date()
        ) ?? Date()
        return today > Date()
            ? today
            : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
