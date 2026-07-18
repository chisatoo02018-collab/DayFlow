import Foundation
import Observation
import Photos

/// Maintains a metadata-only, on-device index of the user's Photos library.
///
/// Raw images, thumbnails, faces and OCR never enter this service. The persistent PhotoKit
/// change token makes refreshes incremental after the first scan; an expired token falls back
/// to a full metadata scan so the index repairs itself instead of silently going stale.
@MainActor
@Observable
final class PhotoMetadataService: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var records: [String: PhotoAssetMetadata] = [:]
    private(set) var lastSyncAt: Date?
    private(set) var isSyncing = false
    private(set) var lastError: String?

    private let library = PHPhotoLibrary.shared()
    private let indexURL: URL
    private let tokenURL: URL
    private var isObserving = false

    override init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = applicationSupport.appendingPathComponent("VisualLog", isDirectory: true)
        indexURL = directory.appendingPathComponent("photo-metadata.json")
        tokenURL = directory.appendingPathComponent("photo-change-token.data")
        super.init()
        loadIndex()
        if isAuthorized { startObserving() }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var isFullAccess: Bool { authorizationStatus == .authorized }

    var summary: PhotoMetadataSummary {
        let start = Calendar.current.startOfDay(for: Date())
        var value = PhotoMetadataSummary(total: records.count)
        for record in records.values {
            if let createdAt = record.createdAt, createdAt >= start { value.today += 1 }
            if record.mediaKind == .video { value.videos += 1 }
            if record.isFavorite { value.favorites += 1 }
            if record.latitude != nil && record.longitude != nil { value.withLocation += 1 }
        }
        return value
    }

    func requestAccess() async {
        guard authorizationStatus == .notDetermined else {
            await refreshIfAuthorized()
            return
        }
        authorizationStatus = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
        guard isAuthorized else { return }
        startObserving()
        await sync()
    }

    /// Safe at launch/foreground: it never presents a system prompt.
    func refreshIfAuthorized() async {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard isAuthorized else { return }
        startObserving()
        await sync()
    }

    func sync() async {
        guard isAuthorized, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        let existing = records
        let indexURL = indexURL
        let tokenURL = tokenURL
        do {
            let result = try await Task.detached(priority: .utility) {
                try Self.scan(existing: existing, indexURL: indexURL, tokenURL: tokenURL)
            }.value
            records = result.records
            lastSyncAt = result.syncedAt
        } catch is CancellationError {
            // View lifecycle cancellation is expected; keep the previous valid index.
        } catch {
            lastError = error.localizedDescription
        }
        isSyncing = false
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            await self?.sync()
        }
    }

    private func startObserving() {
        guard !isObserving else { return }
        library.register(self)
        isObserving = true
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([String: PhotoAssetMetadata].self, from: data)
        else { return }
        records = decoded
        lastSyncAt = (try? FileManager.default.attributesOfItem(atPath: indexURL.path)[.modificationDate]) as? Date
    }

    private struct ScanResult: Sendable {
        var records: [String: PhotoAssetMetadata]
        var syncedAt: Date
    }

    nonisolated private static func scan(
        existing: [String: PhotoAssetMetadata],
        indexURL: URL,
        tokenURL: URL
    ) throws -> ScanResult {
        let library = PHPhotoLibrary.shared()
        var indexed = existing
        var tokenToSave: PHPersistentChangeToken

        if FileManager.default.fileExists(atPath: indexURL.path),
           let token = loadToken(from: tokenURL) {
            do {
                let changes = try library.fetchPersistentChanges(since: token)
                var changedIDs = Set<String>()
                var deletedIDs = Set<String>()
                var newestToken = token
                for change in changes {
                    newestToken = change.changeToken
                    let details = try change.changeDetails(for: .asset)
                    changedIDs.formUnion(details.insertedLocalIdentifiers)
                    changedIDs.formUnion(details.updatedLocalIdentifiers)
                    deletedIDs.formUnion(details.deletedLocalIdentifiers)
                }
                for identifier in deletedIDs { indexed.removeValue(forKey: identifier) }
                applyAssets(with: Array(changedIDs), to: &indexed)
                tokenToSave = newestToken
            } catch {
                // Token expiry or an incompatible prior token: rebuild instead of leaving gaps.
                indexed = fullScan()
                tokenToSave = library.currentChangeToken
            }
        } else {
            indexed = fullScan()
            tokenToSave = library.currentChangeToken
        }

        try persist(indexed, indexURL: indexURL, token: tokenToSave, tokenURL: tokenURL)
        return ScanResult(records: indexed, syncedAt: Date())
    }

    nonisolated private static func fullScan() -> [String: PhotoAssetMetadata] {
        let result = PHAsset.fetchAssets(with: nil)
        var indexed: [String: PhotoAssetMetadata] = [:]
        indexed.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            indexed[asset.localIdentifier] = PhotoAssetMetadata(asset: asset)
        }
        return indexed
    }

    nonisolated private static func applyAssets(
        with identifiers: [String],
        to indexed: inout [String: PhotoAssetMetadata]
    ) {
        guard !identifiers.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        for index in 0..<result.count {
            let asset = result.object(at: index)
            indexed[asset.localIdentifier] = PhotoAssetMetadata(asset: asset)
        }
    }

    nonisolated private static func loadToken(from url: URL) -> PHPersistentChangeToken? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    }

    nonisolated private static func persist(
        _ records: [String: PhotoAssetMetadata],
        indexURL: URL,
        token: PHPersistentChangeToken,
        tokenURL: URL
    ) throws {
        let directory = indexURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        try tokenData.write(to: tokenURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
