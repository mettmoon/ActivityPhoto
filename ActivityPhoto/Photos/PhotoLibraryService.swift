import AppKit
import GeoshopCore
import Photos

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
