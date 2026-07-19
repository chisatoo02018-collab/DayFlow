import Foundation
import Observation

#if FAMILY_CONTROLS_ENABLED
import FamilyControls
#endif

/// Stable UI boundary for Screen Time while the distribution entitlement is pending.
/// Enabling `FAMILY_CONTROLS_ENABLED` is intentionally a separate, reviewed signing change.
@MainActor
@Observable
final class ScreenTimeService {
    enum Status: Equatable {
        case entitlementRequired
        case notDetermined
        case approved
        case denied
    }

    private(set) var status: Status = .entitlementRequired
    private(set) var isRequesting = false
    private(set) var lastError: String?

    init() { refresh() }

    var isCapabilityConfigured: Bool {
        #if FAMILY_CONTROLS_ENABLED
        true
        #else
        false
        #endif
    }

    func refresh() {
        #if FAMILY_CONTROLS_ENABLED
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined: status = .notDetermined
        case .approved, .approvedWithDataAccess: status = .approved
        case .denied: status = .denied
        @unknown default: status = .denied
        }
        #else
        status = .entitlementRequired
        #endif
    }

    func requestAccess() async {
        #if FAMILY_CONTROLS_ENABLED
        guard !isRequesting else { return }
        isRequesting = true
        lastError = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        isRequesting = false
        #else
        lastError = "Apple DeveloperでFamily Controls配布権限が承認された後に有効化できます。"
        #endif
    }
}
