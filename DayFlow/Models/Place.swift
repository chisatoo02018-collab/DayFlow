import CoreLocation
import Foundation
import SwiftUI

/// What a place means for the day's accounting. Only `office` maps cleanly onto an
/// activity (仕事); `home` deliberately does not — time at home could be 睡眠/家事/娯楽,
/// so the ring is never auto-painted from it.
enum PlaceKind: String, Codable, CaseIterable {
    case home
    case office
    case other

    var label: String {
        switch self {
        case .home: return "自宅"
        case .office: return "職場"
        case .other: return "その他"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .office: return "building.2.fill"
        case .other: return "mappin"
        }
    }

    /// Color on the 所在地 ring. Distinct from the activity palette so the two rings
    /// never read as the same information.
    var colorHex: String {
        switch self {
        case .home: return "#5C7CFA"
        case .office: return "#E8590C"
        case .other: return "#868E96"
        }
    }

    var color: Color { Color(hex: colorHex) }
}

/// A geofenced location the app watches. Coordinates are always user-supplied
/// (「現在地をここに設定」or manual entry) — never shipped in the binary.
struct Place: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var kind: PlaceKind
    var latitude: Double
    var longitude: Double
    /// iOS caps monitored regions at a device-dependent max radius; 100–300m suits a
    /// building. Too small and geofence entry is missed, too large and the commute
    /// route trips it.
    var radiusMeters: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var region: CLCircularRegion {
        let r = CLCircularRegion(center: coordinate, radius: radiusMeters, identifier: id)
        r.notifyOnEntry = true
        r.notifyOnExit = true
        return r
    }

    init(id: String = UUID().uuidString, name: String, kind: PlaceKind,
         latitude: Double, longitude: Double, radiusMeters: Double = 200) {
        self.id = id
        self.name = name
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }
}

/// Persists the user's places. Empty by default — the app ships with no coordinates,
/// so a fresh install asks the user to set them from their current location.
@Observable
final class PlaceStore {
    private(set) var places: [Place] = []

    private static let key = "dayflow.places"

    init() {
        load()
    }

    var home: Place? { places.first { $0.kind == .home } }
    var office: Place? { places.first { $0.kind == .office } }
    var isConfigured: Bool { !places.isEmpty }

    func place(withID id: String) -> Place? { places.first { $0.id == id } }

    /// Replaces the place of the same `kind` when one exists (there is only ever one
    /// home and one office), otherwise appends.
    func upsert(_ place: Place) {
        if place.kind != .other, let idx = places.firstIndex(where: { $0.kind == place.kind }) {
            places[idx] = place
        } else if let idx = places.firstIndex(where: { $0.id == place.id }) {
            places[idx] = place
        } else {
            places.append(place)
        }
        persist()
    }

    func remove(_ place: Place) {
        places.removeAll { $0.id == place.id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Place].self, from: data)
        else { return }
        places = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
