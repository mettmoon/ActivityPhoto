import AppKit
import CoreLocation
import GeoshopCore
import Photos

enum LibraryApplyError: LocalizedError {
    case missing(count: Int)

    var errorDescription: String? {
        switch self {
        case .missing(let count): "보관함에서 찾을 수 없는 사진이 \(count)장 있습니다. 목록에서 제거한 뒤 다시 시도하세요."
        }
    }
}

/// 사진 앱 보관함 접근 (PhotoKit). 편집(촬영일·위치 변경)까지 하려면 읽기·쓰기 전체 권한이 필요하다.
@MainActor
final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private let imageManager = PHCachingImageManager()

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var hasFullAccess: Bool { authorizationStatus == .authorized }

    func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func assets(for identifiers: [String]) -> [String: PHAsset] {
        guard !identifiers.isEmpty else { return [:] }
        var result: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil).enumerateObjects { asset, _, _ in
            result[asset.localIdentifier] = asset
        }
        return result
    }

    /// 선택기에서 고른 식별자 → 추가 입력. 찾을 수 없는 식별자는 빠진다.
    func inputs(for identifiers: [String]) -> [LibraryPhotoInput] {
        let assets = assets(for: identifiers)
        return identifiers.compactMap { id in
            guard let asset = assets[id], asset.mediaType == .image else { return nil }
            let resources = PHAssetResource.assetResources(for: asset)
            let name = resources.first { $0.type == .photo }?.filename ?? resources.first?.filename ?? "사진"
            return LibraryPhotoInput(
                identifier: id,
                fileName: name,
                creationDate: asset.creationDate,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude
            )
        }
    }

    func availability(for identifiers: [String]) -> [String: PhotoAvailability] {
        guard hasFullAccess else { return [:] }
        let assets = assets(for: identifiers)
        var result: [String: PhotoAvailability] = [:]
        for id in identifiers {
            if let asset = assets[id] {
                result[id] = asset.canPerform(.properties) ? .available : .notEditable
            } else {
                result[id] = .missing
            }
        }
        return result
    }

    /// 보관함 사진의 촬영일·위치를 바꾼다 (기획서 §4.4.1). 원본 파일은 건드리지 않는다.
    /// 사진 앱의 확인 요청이 한 번만 뜨도록 한 번의 변경 묶음으로 처리한다. 묶음 전체가 성공하거나 실패한다.
    func apply(_ changes: [(identifier: String, assignment: Assignment)]) async throws {
        let assets = assets(for: changes.map(\.identifier))
        let missing = changes.filter { assets[$0.identifier] == nil }
        if !missing.isEmpty {
            throw LibraryApplyError.missing(count: missing.count)
        }
        let requests = changes.map { change in
            (asset: assets[change.identifier]!, location: Self.location(for: change.assignment), date: change.assignment.date)
        }
        try await PHPhotoLibrary.shared().performChanges {
            for request in requests {
                let change = PHAssetChangeRequest(for: request.asset)
                change.creationDate = request.date
                change.location = request.location
            }
        }
    }

    private static func location(for assignment: Assignment) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: assignment.latitude, longitude: assignment.longitude),
            altitude: assignment.altitude ?? 0,
            horizontalAccuracy: 5,
            verticalAccuracy: assignment.altitude == nil ? -1 : 5,   // 음수 = 고도 없음
            timestamp: assignment.date
        )
    }

    func thumbnail(for identifier: String, pixelSize: CGFloat) async -> NSImage? {
        guard hasFullAccess, let asset = assets(for: [identifier])[identifier] else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: pixelSize, height: pixelSize)
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
