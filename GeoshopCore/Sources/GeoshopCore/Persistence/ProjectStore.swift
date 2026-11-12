import Foundation
import SwiftData

public enum TrackImportError: Error, Equatable, Sendable {
    /// GPX 파일을 고르지 않음 (프로젝트 생성 시 1개 이상 필수).
    case noFiles
    /// 파일을 읽을 수 없음.
    case unreadable(fileName: String)
    /// GPX 형식 문제.
    case invalidGPX(fileName: String, GPXParseError)
    /// 프로젝트의 마지막 GPX는 지울 수 없음.
    case lastTrack
}

/// GPX를 추가할 때 막지는 않지만 사용자에게 알릴 사항.
public enum TrackImportWarning: Equatable, Sendable {
    /// 추가한 트랙의 시작 위치 시간대가 프로젝트 시간대와 오프셋이 다름 (D10).
    case differentTimeZone(trackName: String, trackTimeZone: TimeZone)
}

/// 프로젝트·GPX 파일의 생성/추가/삭제와 시간대 판별을 맡는다.
/// GPX 원본은 `trackDirectory`로 복사해 두고 SwiftData에는 메타데이터만 저장한다.
@MainActor
public final class ProjectStore {
    public let context: ModelContext
    public let trackDirectory: URL
    private let timeZoneResolver: any TimeZoneResolving
    private let fallbackTimeZone: TimeZone
    /// 사진 파일 북마크 옵션. 샌드박스 앱은 보안 범위 북마크(app-scope)를 쓴다.
    public var bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    public var bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]

    public init(
        context: ModelContext,
        trackDirectory: URL,
        timeZoneResolver: any TimeZoneResolving = MapKitTimeZoneResolver(),
        fallbackTimeZone: TimeZone = .current
    ) {
        self.context = context
        self.trackDirectory = trackDirectory
        self.timeZoneResolver = timeZoneResolver
        self.fallbackTimeZone = fallbackTimeZone
    }

    /// 앱 컨테이너의 Application Support/Geoshop/Tracks.
    public static var defaultTrackDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "Geoshop", directoryHint: .isDirectory)
            .appending(path: "Tracks", directoryHint: .isDirectory)
    }

    // MARK: - 프로젝트

    /// GPX를 모두 검증·복사한 뒤 프로젝트를 만든다. 하나라도 실패하면 아무것도 남기지 않는다.
    /// - Parameter name: 비우면 첫 GPX의 이름 → 첫 트랙 이름 → 파일 이름 순으로 정한다.
    @discardableResult
    public func createProject(name: String?, sourceKind: PhotoSourceKind, gpxURLs: [URL]) async throws -> Project {
        guard !gpxURLs.isEmpty else { throw TrackImportError.noFiles }
        let imported = try importFiles(gpxURLs, startingColorIndex: 0)

        let earliest = imported.compactMap(\.document.firstPoint).min { $0.time < $1.time }
        var timeZone: TimeZone?
        if let earliest {
            timeZone = await timeZoneResolver.timeZone(latitude: earliest.latitude, longitude: earliest.longitude)
        }

        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let project = Project(
            name: trimmed.isEmpty ? imported[0].track.displayName : trimmed,
            sourceKind: sourceKind,
            timeZoneID: (timeZone ?? fallbackTimeZone).identifier,
            timeZoneIsAuto: true,
            timeZoneNeedsReview: timeZone == nil
        )
        context.insert(project)
        for item in imported {
            project.tracks.append(item.track)
        }
        try save()
        return project
    }

    public func deleteProject(_ project: Project) throws {
        let fileNames = project.tracks.map(\.storedFileName)
        context.delete(project)
        try save()
        for fileName in fileNames {
            try? FileManager.default.removeItem(at: fileURL(storedFileName: fileName))
        }
    }

    // MARK: - GPX 추가/삭제

    /// 기존 프로젝트에 GPX를 추가한다. 하나라도 형식이 잘못되면 아무것도 추가하지 않는다.
    /// 시간대가 다른 트랙은 추가하되 경고를 돌려준다 (D10).
    @discardableResult
    public func addTracks(_ urls: [URL], to project: Project) async throws -> [TrackImportWarning] {
        guard !urls.isEmpty else { return [] }
        let usedColors = Set(project.tracks.map(\.colorIndex))
        let imported = try importFiles(urls, startingColorIndex: 0, skippingColors: usedColors)

        var warnings: [TrackImportWarning] = []
        let projectZone = project.timeZone
        for item in imported {
            guard let first = item.document.firstPoint,
                  let zone = await timeZoneResolver.timeZone(latitude: first.latitude, longitude: first.longitude)
            else { continue }
            if !zone.hasSameOffset(as: projectZone, at: first.time) {
                warnings.append(.differentTimeZone(trackName: item.track.displayName, trackTimeZone: zone))
            }
        }

        for item in imported {
            project.tracks.append(item.track)
        }
        try save()
        return warnings
    }

    public func removeTrack(_ track: TrackFile, from project: Project) throws {
        guard project.tracks.count > 1 else { throw TrackImportError.lastTrack }
        let fileName = track.storedFileName
        project.tracks.removeAll { $0.id == track.id }
        context.delete(track)
        try save()
        try? FileManager.default.removeItem(at: fileURL(storedFileName: fileName))
    }

    // MARK: - 시간대

    /// 사용자가 시간대를 직접 고른다.
    public func setTimeZone(_ timeZone: TimeZone, for project: Project) throws {
        project.timeZoneID = timeZone.identifier
        project.timeZoneIsAuto = false
        project.timeZoneNeedsReview = false
        try save()
    }

    /// 자동 판별로 되돌린다. 판별에 실패하면 기존 값을 두고 `timeZoneNeedsReview`를 켠다.
    public func resetTimeZoneToAutomatic(for project: Project) async throws {
        let documents = try project.tracks.map { try document(for: $0) }
        let earliest = documents.compactMap(\.firstPoint).min { $0.time < $1.time }
        var zone: TimeZone?
        if let earliest {
            zone = await timeZoneResolver.timeZone(latitude: earliest.latitude, longitude: earliest.longitude)
        }
        if let zone { project.timeZoneID = zone.identifier }
        project.timeZoneIsAuto = true
        project.timeZoneNeedsReview = zone == nil
        try save()
    }

    // MARK: - 트랙 데이터 읽기

    public func fileURL(for track: TrackFile) -> URL {
        fileURL(storedFileName: track.storedFileName)
    }

    public func document(for track: TrackFile) throws -> GPXDocument {
        try GPXParser.parse(contentsOf: fileURL(for: track))
    }

    /// 프로젝트의 모든 GPX를 읽어 타임라인을 만든다. 세그먼트의 `documentIndex`는 `sortedTracks` 순서.
    public func timeline(for project: Project) throws -> TrackTimeline {
        TrackTimeline(documents: try project.sortedTracks.map { try document(for: $0) })
    }

    // MARK: - 내부

    private struct ImportedFile {
        let track: TrackFile
        let document: GPXDocument
    }

    private func importFiles(
        _ urls: [URL],
        startingColorIndex: Int,
        skippingColors usedColors: Set<Int> = []
    ) throws -> [ImportedFile] {
        // 1) 모두 읽고 검증한 뒤
        var parsed: [(url: URL, data: Data, document: GPXDocument)] = []
        for url in urls {
            let fileName = url.lastPathComponent
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                throw TrackImportError.unreadable(fileName: fileName)
            }
            do {
                parsed.append((url, data, try GPXParser.parse(data: data)))
            } catch let error as GPXParseError {
                throw TrackImportError.invalidGPX(fileName: fileName, error)
            }
        }

        // 2) 복사한다. 중간 실패 시 이미 쓴 파일은 지운다.
        try FileManager.default.createDirectory(at: trackDirectory, withIntermediateDirectories: true)
        var written: [URL] = []
        var result: [ImportedFile] = []
        var colors = usedColors
        do {
            for item in parsed {
                let id = UUID()
                let storedFileName = "\(id.uuidString).gpx"
                let destination = fileURL(storedFileName: storedFileName)
                try item.data.write(to: destination, options: .atomic)
                written.append(destination)

                let colorIndex = Self.nextColorIndex(excluding: colors, from: startingColorIndex)
                colors.insert(colorIndex)
                let document = item.document
                let fallbackName = item.url.deletingPathExtension().lastPathComponent
                let track = TrackFile(
                    id: id,
                    displayName: document.name ?? document.tracks.first?.name ?? fallbackName,
                    originalFileName: item.url.lastPathComponent,
                    storedFileName: storedFileName,
                    colorIndex: colorIndex,
                    startTime: document.startTime!,
                    endTime: document.endTime!,
                    pointCount: document.pointCount,
                    distance: TrackTimeline(documents: [document]).totalDistance
                )
                result.append(ImportedFile(track: track, document: document))
            }
        } catch {
            for url in written { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return result
    }

    private static func nextColorIndex(excluding used: Set<Int>, from start: Int) -> Int {
        var index = start
        while used.contains(index) { index += 1 }
        return index
    }

    private func fileURL(storedFileName: String) -> URL {
        trackDirectory.appending(path: storedFileName, directoryHint: .notDirectory)
    }

    /// 컨텍스트에 바뀐 내용이 있으면 저장한다.
    public func save() throws {
        if context.hasChanges { try context.save() }
    }
}
