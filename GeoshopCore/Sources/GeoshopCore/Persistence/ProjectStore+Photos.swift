import Foundation
import SwiftData

public enum PhotoImportError: Error, Equatable, Sendable {
    /// 프로젝트 사진 소스와 다른 종류의 사진을 추가하려 함 (D2).
    case wrongSource
    /// 다시 연결: 이미지가 아니거나 읽을 수 없음.
    case unreadable(fileName: String)
    /// 다시 연결: 같은 파일이 이미 프로젝트에 있음.
    case duplicate(fileName: String)
}

/// 보관함 사진 추가 입력. PhotoKit 조회는 앱이 하고 값만 넘긴다.
public struct LibraryPhotoInput: Sendable, Equatable {
    public var identifier: String
    public var fileName: String
    public var creationDate: Date?
    public var latitude: Double?
    public var longitude: Double?

    public init(identifier: String, fileName: String, creationDate: Date?, latitude: Double?, longitude: Double?) {
        self.identifier = identifier
        self.fileName = fileName
        self.creationDate = creationDate
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct PhotoAddResult: Sendable, Equatable {
    public var added: Int = 0
    /// 이미 프로젝트에 있어 건너뜀 (§4.2: 중복 추가는 무시).
    public var duplicates: Int = 0
    /// 이미지가 아니거나 읽을 수 없어 건너뛴 파일 이름.
    public var skipped: [String] = []

    public init(added: Int = 0, duplicates: Int = 0, skipped: [String] = []) {
        self.added = added
        self.duplicates = duplicates
        self.skipped = skipped
    }
}

extension ProjectStore {
    // MARK: - 추가

    /// 파일·폴더를 받아 이미지 파일을 참조로 추가한다. 폴더는 하위까지 뒤진다.
    @discardableResult
    public func addPhotos(fileURLs: [URL], to project: Project) throws -> PhotoAddResult {
        guard project.sourceKind == .files else { throw PhotoImportError.wrongSource }

        let scoped = fileURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

        var known = Set(project.photos.compactMap { $0.filePath.map(Self.pathKey) })
        var result = PhotoAddResult()
        for url in ImageFiles.collectImages(in: fileURLs) {
            let key = Self.pathKey(url.path)
            guard !known.contains(key) else { result.duplicates += 1; continue }
            guard let info = ImageFiles.readInfo(at: url),
                  let bookmark = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            else { result.skipped.append(url.lastPathComponent); continue }

            known.insert(key)
            project.photos.append(PhotoRef(
                bookmarkData: bookmark,
                filePath: url.standardizedFileURL.path,
                fileName: url.lastPathComponent,
                isWritableFormat: info.isWritableFormat,
                originalCaptureDate: info.captureDate,
                originalCaptureLocalText: info.captureDate == nil ? info.captureLocalText : nil,
                originalLatitude: info.latitude,
                originalLongitude: info.longitude
            ))
            result.added += 1
        }
        try save()
        return result
    }

    /// 보관함 사진을 참조로 추가한다.
    @discardableResult
    public func addLibraryPhotos(_ inputs: [LibraryPhotoInput], to project: Project) throws -> PhotoAddResult {
        guard project.sourceKind == .photoLibrary else { throw PhotoImportError.wrongSource }
        var known = Set(project.photos.compactMap(\.assetIdentifier))
        var result = PhotoAddResult()
        for input in inputs {
            guard known.insert(input.identifier).inserted else { result.duplicates += 1; continue }
            project.photos.append(PhotoRef(
                assetIdentifier: input.identifier,
                fileName: input.fileName,
                isWritableFormat: true,
                originalCaptureDate: input.creationDate,
                originalLatitude: input.latitude,
                originalLongitude: input.longitude
            ))
            result.added += 1
        }
        try save()
        return result
    }

    // MARK: - 제거·다시 연결

    /// 목록에서 제거. 원본 사진은 건드리지 않는다.
    public func removePhotos(_ photos: [PhotoRef], from project: Project) throws {
        let ids = Set(photos.map(\.id))
        project.photos.removeAll { ids.contains($0.id) }
        for photo in photos { context.delete(photo) }
        try save()
    }

    /// 찾을 수 없는 파일 사진을 다른 파일로 다시 연결한다 (§4.5). 할당 정보는 유지한다.
    public func relink(_ photo: PhotoRef, to url: URL, in project: Project) throws {
        guard project.sourceKind == .files else { throw PhotoImportError.wrongSource }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let key = Self.pathKey(url.path)
        if project.photos.contains(where: { $0.id != photo.id && $0.filePath.map(Self.pathKey) == key }) {
            throw PhotoImportError.duplicate(fileName: url.lastPathComponent)
        }
        guard let info = ImageFiles.readInfo(at: url),
              let bookmark = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { throw PhotoImportError.unreadable(fileName: url.lastPathComponent) }

        photo.bookmarkData = bookmark
        photo.filePath = url.standardizedFileURL.path
        photo.fileName = url.lastPathComponent
        photo.isWritableFormat = info.isWritableFormat
        try save()
    }

    // MARK: - 참조 해석

    /// 파일 사진의 북마크를 해석해 현재 URL을 돌려준다. 파일이 없으면 nil.
    /// 파일이 옮겨졌으면 경로를 갱신하고, 북마크가 낡았으면 새로 만든다.
    /// 돌려받은 URL을 읽고 쓸 때는 `startAccessingSecurityScopedResource()`로 감싸야 한다.
    public func resolveFileURL(for photo: PhotoRef) -> URL? {
        guard let data = photo.bookmarkData else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: bookmarkResolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)
        else { return nil }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        if isStale, let fresh = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            photo.bookmarkData = fresh
        }
        let path = url.standardizedFileURL.path
        if photo.filePath != path {
            photo.filePath = path
            photo.fileName = url.lastPathComponent
        }
        return url
    }

    static func pathKey(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
    }
}
