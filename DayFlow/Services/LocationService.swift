import CoreLocation
import Foundation
import Observation

/// A geofence crossing. The raw, append-only record — segments are derived from it.
struct LocationEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case enter, exit }
    var id: UUID
    var placeID: String
    var kind: Kind
    var date: Date

    init(id: UUID = UUID(), placeID: String, kind: Kind, date: Date) {
        self.id = id
        self.placeID = placeID
        self.kind = kind
        self.date = date
    }
}

/// A resolved stretch of a day spent at a place, or travelling between two of them.
struct LocationSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        case stay(placeID: String, placeKind: PlaceKind)
        /// Between leaving one known place and arriving at another — a real commute.
        case moving
        /// Outside every known place for long enough that we can't call it a commute.
        case away
    }
    var id = UUID()
    var kind: Kind
    /// Minutes from midnight, clamped to the day.
    var start: Int
    var end: Int

    var durationMinutes: Int { max(0, end - start) }
}

/// Watches the user's places with Core Location region monitoring and turns crossings
/// into per-day location segments.
///
/// Region monitoring (not `BGProcessingTask`) is the whole point: iOS relaunches the app
/// on a geofence crossing even when it has been terminated, so recording is genuinely
/// automatic. `BGProcessingTask` is scheduled at the OS's discretion and is what left
/// LifeLog with a single day of data before it was retired — it is deliberately unused here.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var events: [LocationEvent] = []
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Set when the user's current position is requested for 「現在地をここに設定」.
    private(set) var currentLocation: CLLocation?
    var onCurrentLocation: ((CLLocation) -> Void)?

    /// When on, office stays and commutes fill *empty* slots of the 実績 ring. The 所在地
    /// ring is drawn regardless — it never touches the user's own accounting.
    var importsToRing: Bool = UserDefaults.standard.bool(forKey: ringImportKey) {
        didSet { UserDefaults.standard.set(importsToRing, forKey: Self.ringImportKey) }
    }

    private let manager = CLLocationManager()
    private let placeStore: PlaceStore
    private static let eventsKey = "dayflow.locationEvents"
    private static let ringImportKey = "dayflow.locationImportsToRing"
    /// A gap between two known places longer than this isn't a commute — the user did
    /// something else in between, and we won't claim to know what.
    private static let maxCommuteMinutes = 180

    init(placeStore: PlaceStore) {
        self.placeStore = placeStore
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        authorizationStatus = manager.authorizationStatus
        loadEvents()
    }

    var isAuthorizedAlways: Bool { authorizationStatus == .authorizedAlways }

    // MARK: - Permission & monitoring

    /// Always-authorization is required for the app to be woken on a crossing while it
    /// isn't running. When-in-use only records while the app is open.
    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// (Re)registers geofences for every configured place. Safe to call repeatedly.
    func refreshMonitoring() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        guard authorizationStatus == .authorizedAlways else { return }
        for place in placeStore.places {
            manager.startMonitoring(for: place.region)
            // Monitoring only fires on a *crossing*; ask once for the current state so a
            // place the user is already sitting inside registers as a stay.
            manager.requestState(for: place.region)
        }
    }

    func requestCurrentLocation() {
        if authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.requestLocation()
    }

    // MARK: - Events

    private func record(placeID: String, kind: LocationEvent.Kind, date: Date = Date()) {
        // Geofences can re-fire the same state; ignore a repeat of the last known state.
        if let last = events.last(where: { $0.placeID == placeID }), last.kind == kind {
            return
        }
        events.append(LocationEvent(placeID: placeID, kind: kind, date: date))
        trimAndPersist()
    }

    private func trimAndPersist() {
        // 120 days is far more history than the ring or the widget summary ever reads.
        let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: Date()) ?? .distantPast
        events.removeAll { $0.date < cutoff }
        events.sort { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Self.eventsKey)
        }
    }

    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: Self.eventsKey),
              let decoded = try? JSONDecoder().decode([LocationEvent].self, from: data)
        else { return }
        events = decoded.sorted { $0.date < $1.date }
    }

    #if DEBUG
    /// Seeds events so the ring can be exercised in the simulator, where geofences don't fire.
    func debugSeed(_ seeded: [LocationEvent]) {
        events = seeded.sorted { $0.date < $1.date }
        trimAndPersist()
    }
    #endif

    // MARK: - Segments

    /// Resolves the day's crossings into stays and commutes.
    ///
    /// A stay runs from an `enter` to the matching `exit` (clamped to the day, so an
    /// overnight stay at home shows from 00:00). A gap between leaving one place and
    /// arriving at another becomes `.moving` when it's short enough to be a commute,
    /// otherwise `.away`.
    func segments(for day: Date) -> [LocationSegment] {
        let cal = Calendar.current
        guard let dayStart = cal.dateInterval(of: .day, for: day)?.start,
              let dayEnd = cal.dateInterval(of: .day, for: day)?.end
        else { return [] }

        func minutes(_ date: Date) -> Int {
            let clamped = min(max(date, dayStart), dayEnd)
            return Int(clamped.timeIntervalSince(dayStart) / 60)
        }

        // The state entering the day: the last event before midnight decides whether the
        // user was already inside a place at 00:00.
        var openPlaceID: String?
        var openSince = dayStart
        if let prior = events.last(where: { $0.date < dayStart }), prior.kind == .enter {
            openPlaceID = prior.placeID
        }

        var result: [LocationSegment] = []
        var lastExitAt: Date?
        var lastExitPlaceID: String?

        func appendStay(_ placeID: String, from: Date, to: Date) {
            guard let place = placeStore.place(withID: placeID) else { return }
            let s = minutes(from), e = minutes(to)
            guard e > s else { return }
            result.append(LocationSegment(kind: .stay(placeID: placeID, placeKind: place.kind),
                                          start: s, end: e))
        }

        for event in events where event.date >= dayStart && event.date < dayEnd {
            switch event.kind {
            case .enter:
                // Arriving closes any travel that started when we left the previous place.
                if let exitAt = lastExitAt, lastExitPlaceID != nil {
                    let gap = Int(event.date.timeIntervalSince(exitAt) / 60)
                    let s = minutes(exitAt), e = minutes(event.date)
                    if e > s {
                        result.append(LocationSegment(
                            kind: gap <= Self.maxCommuteMinutes ? .moving : .away,
                            start: s, end: e))
                    }
                    lastExitAt = nil
                    lastExitPlaceID = nil
                }
                openPlaceID = event.placeID
                openSince = event.date
            case .exit:
                if let open = openPlaceID, open == event.placeID {
                    appendStay(open, from: max(openSince, dayStart), to: event.date)
                }
                openPlaceID = nil
                lastExitAt = event.date
                lastExitPlaceID = event.placeID
            }
        }

        // Still inside a place when the day ended (or now, for today).
        if let open = openPlaceID {
            let until = cal.isDateInToday(day) ? min(Date(), dayEnd) : dayEnd
            appendStay(open, from: max(openSince, dayStart), to: until)
        }

        return result.sorted { $0.start < $1.start }
    }

    /// True when the day contains a stay at a place marked `office`.
    func didAttendOffice(on day: Date) -> Bool {
        segments(for: day).contains { seg in
            if case .stay(_, let kind) = seg.kind { return kind == .office }
            return false
        }
    }

    /// Total minutes at the office that day (0 when absent).
    func officeMinutes(on day: Date) -> Int {
        segments(for: day).reduce(0) { total, seg in
            if case .stay(_, let kind) = seg.kind, kind == .office {
                return total + seg.durationMinutes
            }
            return total
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        refreshMonitoring()
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        record(placeID: region.identifier, kind: .enter)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        record(placeID: region.identifier, kind: .exit)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState,
                         for region: CLRegion) {
        // Only used to catch "already inside" at startup; an outside state here is not a
        // crossing and must not fabricate an exit.
        if state == .inside { record(placeID: region.identifier, kind: .enter) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
        onCurrentLocation?(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient (e.g. no fix indoors); the next crossing or request will retry.
    }
}
