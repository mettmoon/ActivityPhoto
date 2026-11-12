import AppKit
import GeoshopCore
import ImageIO
import Observation

/// 프로젝트 사진 목록의 화면 상태: 참조 확인 결과, 선택, 정렬·필터 (기획서 §4.2, §4.5, §5).
@Observable
final class PhotoCatalog {
    enum SortOrder: String, CaseIterable, Identifiable {
        case added, originalDate, assignedDate
        var id: Self { self }
        var title: String {
            switch self {
            case .added: "추가순"
            case .originalDate: "기존 촬영시각"
            case .assignedDate: "할당 시각"
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, unassigned, pending
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "전체"
            case .unassigned: "미할당"
            case .pending: "대기"
            }
        }
    }

    private(set) var availability: [UUID: PhotoAvailability] = [:]
    private(set) var fileURLs: [UUID: URL] = [:]
    private(set) var isRefreshing = false
    var selection: Set<UUID> = []
    private var anchor: UUID?
    var sortOrder: SortOrder = .added
    var filter: Filter = .all

    func status(of photo: PhotoRef) -> PhotoStatus {
        photo.status(availability: availability[photo.id] ?? .unknown)
    }

    func visiblePhotos(in project: Project) -> [PhotoRef] {
        let zone = project.timeZone
        let filtered = project.photos.filter { photo in
            switch filter {
            case .all: true
            case .unassigned: status(of: photo) == .unassigned
            case .pending: status(of: photo) == .pending
            }
        }
        func key(_ photo: PhotoRef) -> Date? {
            switch sortOrder {
            case .added: photo.addedAt
            case .originalDate: photo.originalDate(in: zone)
            case .assignedDate: photo.assignment?.date
            }
        }
        // 값이 없는 사진은 뒤로, 같으면 추가순·파일 이름순
        return filtered.sorted { a, b in
            switch (key(a), key(b)) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                return (a.addedAt, a.fileName) < (b.addedAt, b.fileName)
            }
        }
    }

    func selectedPhotos(in project: Project) -> [PhotoRef] {
        project.photos.filter { selection.contains($0.id) }
    }

    // MARK: - 선택 (클릭 / ⌘ 클릭 / ⇧ 클릭)

    func click(_ photo: PhotoRef, in ordered: [PhotoRef], modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor, let from = ordered.firstIndex(where: { $0.id == anchor }),
           let to = ordered.firstIndex(where: { $0.id == photo.id }) {
            let range = min(from, to)...max(from, to)
            let ids = ordered[range].map(\.id)
            if modifiers.contains(.command) { selection.formUnion(ids) } else { selection = Set(ids) }
            return
        }
        if modifiers.contains(.command) {
            if selection.contains(photo.id) { selection.remove(photo.id) } else { selection.insert(photo.id) }
        } else {
            selection = [photo.id]
        }
        anchor = photo.id
    }

    func selectAll(_ photos: [PhotoRef]) {
        selection = Set(photos.map(\.id))
    }

    func clearSelection() {
        selection = []
        anchor = nil
    }

    // MARK: - 참조 확인

    /// 원본이 아직 있는지 확인한다. 파일은 북마크 해석, 보관함은 PhotoKit 조회.
    func refresh(project: Project, store: ProjectStore?, library: PhotoLibraryService? = nil) {
        let library = library ?? .shared
        isRefreshing = true
        defer { isRefreshing = false }
        var availability: [UUID: PhotoAvailability] = [:]
        var urls: [UUID: URL] = [:]
        switch project.sourceKind {
        case .files:
            for photo in project.photos {
                if let url = store?.resolveFileURL(for: photo) {
                    urls[photo.id] = url
                    availability[photo.id] = .available
                } else {
                    availability[photo.id] = .missing
                }
            }
            try? store?.save()
        case .photoLibrary:
            let ids = project.photos.compactMap(\.assetIdentifier)
            let byIdentifier = library.availability(for: ids)
            for photo in project.photos {
                availability[photo.id] = photo.assetIdentifier.flatMap { byIdentifier[$0] } ?? .unknown
            }
        }
        self.availability = availability
        fileURLs = urls
        selection.formIntersection(project.photos.map(\.id))
    }
}

/// 썸네일 캐시. 파일은 ImageIO로 내장 썸네일을 쓰고, 보관함은 PhotoKit에서 받는다.
@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()
    static let pixelSize: CGFloat = 320

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 2_000
    }

    func thumbnail(for photo: PhotoRef, fileURL: URL?) async -> NSImage? {
        let key = "\(photo.id.uuidString)|\(photo.filePath ?? photo.assetIdentifier ?? "")" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        var image: NSImage?
        if let identifier = photo.assetIdentifier {
            image = await PhotoLibraryService.shared.thumbnail(for: identifier, pixelSize: Self.pixelSize)
        } else if let fileURL {
            let maxPixel = Self.pixelSize
            let cgImage = await Task.detached(priority: .userInitiated) {
                Self.makeThumbnail(url: fileURL, maxPixel: maxPixel)
            }.value
            image = cgImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    nonisolated private static func makeThumbnail(url: URL, maxPixel: CGFloat) -> CGImage? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
