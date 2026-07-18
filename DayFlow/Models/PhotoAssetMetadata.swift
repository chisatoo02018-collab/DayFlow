import Foundation
import Photos

/// Metadata-only representation of a Photos asset. The image/video bytes never leave Photos.
struct PhotoAssetMetadata: Codable, Identifiable, Sendable {
    enum MediaKind: String, Codable, Sendable {
        case image
        case video
        case audio
        case unknown
    }

    var id: String
    var createdAt: Date?
    var modifiedAt: Date?
    var mediaKind: MediaKind
    var mediaSubtypes: UInt
    var sourceType: UInt
    var durationSeconds: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var isFavorite: Bool
    var isHidden: Bool
    var latitude: Double?
    var longitude: Double?
    var burstIdentifier: String?

    init(asset: PHAsset) {
        id = asset.localIdentifier
        createdAt = asset.creationDate
        modifiedAt = asset.modificationDate
        switch asset.mediaType {
        case .image: mediaKind = .image
        case .video: mediaKind = .video
        case .audio: mediaKind = .audio
        case .unknown: mediaKind = .unknown
        @unknown default: mediaKind = .unknown
        }
        mediaSubtypes = asset.mediaSubtypes.rawValue
        sourceType = asset.sourceType.rawValue
        durationSeconds = asset.duration
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        isFavorite = asset.isFavorite
        isHidden = asset.isHidden
        latitude = asset.location?.coordinate.latitude
        longitude = asset.location?.coordinate.longitude
        burstIdentifier = asset.burstIdentifier
    }
}

struct PhotoMetadataSummary: Sendable {
    var total = 0
    var today = 0
    var videos = 0
    var favorites = 0
    var withLocation = 0
}
