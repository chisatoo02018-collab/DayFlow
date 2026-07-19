import Foundation
import WatchConnectivity

/// Receives wake-time edits from the companion watchOS app and applies them through
/// the iPhone app's canonical ScheduleStore before asking AlarmKit to replace the alarm.
@MainActor
final class WatchWakeScheduleCoordinator: NSObject, WCSessionDelegate {
    static let shared = WatchWakeScheduleCoordinator()

    private weak var scheduleStore: ScheduleStore?
    private var pendingContext: [String: Any]?

    private override init() {
        super.init()
    }

    func configure(scheduleStore: ScheduleStore) {
        self.scheduleStore = scheduleStore
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func publish(time: Date, alarmScheduled: Bool, message: String? = nil) {
        let context = WakeScheduleMessage.wakeTimeState(
            time: time,
            alarmScheduled: alarmScheduled,
            message: message
        )
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingContext = context
            return
        }
        try? session.updateApplicationContext(context)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            guard let self, let context = pendingContext else { return }
            try? session.updateApplicationContext(context)
            pendingContext = nil
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak self] in
            await self?.handle(message, replyHandler: replyHandler)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor [weak self] in
            await self?.handle(userInfo, replyHandler: nil)
        }
    }

    private func handle(
        _ payload: [String: Any],
        replyHandler: (([String: Any]) -> Void)?
    ) async {
        guard let store = scheduleStore else {
            replyHandler?(WakeScheduleMessage.wakeTimeState(
                time: nil,
                alarmScheduled: false,
                message: "iPhoneでDayFlowを一度開いてください。",
                requestID: WakeScheduleMessage.requestID(in: payload)
            ))
            return
        }

        switch WakeScheduleMessage.kind(in: payload) {
        case .setWakeTime:
            guard let time = WakeScheduleMessage.clockTime(in: payload) else { return }
            store.setPlannedWakeTime(time)

            do {
                let outcome = try await SetWakeTimeIntent.scheduleAlarmOutcome(
                    for: time,
                    requestAuthorizationIfNeeded: false
                )
                let response = WakeScheduleMessage.wakeTimeState(
                    time: time,
                    alarmScheduled: outcome.alarmScheduled,
                    message: outcome.message,
                    requestID: WakeScheduleMessage.requestID(in: payload)
                )
                replyHandler?(response)
                publish(
                    time: time,
                    alarmScheduled: outcome.alarmScheduled,
                    message: outcome.message
                )
            } catch {
                let response = WakeScheduleMessage.wakeTimeState(
                    time: time,
                    alarmScheduled: false,
                    message: "予定は保存しました。iPhoneでアラーム設定を確認してください。",
                    requestID: WakeScheduleMessage.requestID(in: payload)
                )
                replyHandler?(response)
                publish(
                    time: time,
                    alarmScheduled: false,
                    message: WakeScheduleMessage.message(in: response)
                )
            }

        case .requestWakeTime:
            // An App Intent may have changed the shared file while the app was suspended.
            store.reloadFromSharedContainer()
            replyHandler?(WakeScheduleMessage.wakeTimeState(
                time: store.nextPlannedWakeTime(),
                alarmScheduled: nil
            ))

        case .wakeTimeState, .none:
            break
        }
    }
}
