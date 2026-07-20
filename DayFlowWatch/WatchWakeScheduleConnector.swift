import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit
import UserNotifications

final class WatchWakeScheduleConnector: NSObject, ObservableObject, WCSessionDelegate, UNUserNotificationCenterDelegate {
    enum SyncState: Equatable {
        case ready
        case sending
        case queued
        case confirmed
        case warning(String)
        case failed
    }

    @Published private(set) var selectedTime: Date
    @Published private(set) var syncState: SyncState = .ready

    private var pendingPayload: [String: Any]?
    private var lastWatchNotificationScheduled: Bool?

    override init() {
        selectedTime = WatchWakeTimeStore.time()
        super.init()
        UNUserNotificationCenter.current().delegate = self

        guard WCSession.isSupported() else {
            syncState = .failed
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func requestLatestTime() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(
            WakeScheduleMessage.requestWakeTime(),
            replyHandler: { [weak self] reply in self?.handle(reply) },
            errorHandler: nil
        )
    }

    func setWakeTime(_ time: Date) {
        selectedTime = time
        persist(time)
        syncState = .sending
        WKInterfaceDevice.current().play(.click)

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let payload = WakeScheduleMessage.setWakeTime(
            hour: components.hour ?? 7,
            minute: components.minute ?? 0
        )
        Task { [weak self] in
            guard let self else { return }
            let scheduled = await WatchWakeNotificationScheduler.schedule(for: time)
            await MainActor.run {
                self.lastWatchNotificationScheduled = scheduled
                if scheduled {
                    self.syncState = .confirmed
                    WKInterfaceDevice.current().play(.success)
                } else {
                    self.syncState = .warning("Watchの通知を許可してください。")
                    WKInterfaceDevice.current().play(.retry)
                }
                self.transmit(payload)
            }
        }
    }

    private func transmit(_ payload: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingPayload = payload
            syncState = .queued
            return
        }

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: { [weak self] reply in self?.handle(reply) },
                errorHandler: { [weak self] _ in self?.queue(payload) }
            )
        } else {
            queue(payload)
        }
    }

    private func queue(_ payload: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let session = WCSession.default
            guard session.activationState == .activated else {
                pendingPayload = payload
                syncState = .queued
                return
            }
            session.transferUserInfo(payload)
            syncState = .queued
        }
    }

    private func handle(_ payload: [String: Any]) {
        guard WakeScheduleMessage.kind(in: payload) == .wakeTimeState else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let time = WakeScheduleMessage.clockTime(in: payload) {
                selectedTime = time
                persist(time)
            }

            if let watchScheduled = lastWatchNotificationScheduled {
                lastWatchNotificationScheduled = nil
                if watchScheduled {
                    syncState = .confirmed
                } else {
                    syncState = .warning("Watchの通知を許可してください。")
                }
                return
            }

            switch WakeScheduleMessage.alarmWasScheduled(in: payload) {
            case true:
                syncState = .confirmed
                WKInterfaceDevice.current().play(.success)
            case false:
                syncState = .warning(
                    WakeScheduleMessage.message(in: payload)
                    ?? "iPhoneでアラームの許可を確認してください。"
                )
                WKInterfaceDevice.current().play(.retry)
            case nil:
                if syncState != .queued { syncState = .ready }
            }
        }
    }

    private func persist(_ time: Date) {
        WatchWakeTimeStore.save(time)
        WidgetCenter.shared.reloadTimelines(ofKind: WatchWakeTimeStore.complicationKind)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard activationState == .activated, error == nil else {
                syncState = .failed
                return
            }
            if let pendingPayload {
                self.pendingPayload = nil
                transmit(pendingPayload)
            } else {
                requestLatestTime()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
