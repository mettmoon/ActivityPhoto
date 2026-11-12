import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import GeoshopCore

/// 테스트용 이미지 파일 생성.
enum ImageFixture {
    struct Meta {
        var dateTimeOriginal: String?
        var offset: String?
        var latitude: Double?
        var longitude: Double?
    }

    static func write(_ url: URL, type: UTType = .jpeg, meta: Meta = Meta()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = context.makeImage()!

        var properties: [CFString: Any] = [:]
        var exif: [CFString: Any] = [:]
        if let d = meta.dateTimeOriginal { exif[kCGImagePropertyExifDateTimeOriginal] = d }
        if let o = meta.offset { exif[kCGImagePropertyExifOffsetTimeOriginal] = o }
        if !exif.isEmpty { properties[kCGImagePropertyExifDictionary] = exif }
        if let lat = meta.latitude, let lon = meta.longitude {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(lat), kCGImagePropertyGPSLatitudeRef: lat < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude: abs(lon), kCGImagePropertyGPSLongitudeRef: lon < 0 ? "W" : "E",
            ]
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }
}

@Suite("이미지 파일")
struct ImageFilesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ImageFilesTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test("EXIF 촬영일시·오프셋·GPS(남·서반구)를 읽는다")
    func readsMetadata() throws {
        let url = root.appending(path: "a.jpg")
        try ImageFixture.write(url, meta: .init(dateTimeOriginal: "2026:05:01 10:05:00", offset: "+09:00", latitude: -33.5, longitude: -70.25))
        let info = try #require(ImageFiles.readInfo(at: url))

        #expect(info.isWritableFormat)
        #expect(info.captureLocalText == "2026:05:01 10:05:00")
        #expect(info.captureOffset == "+09:00")
        #expect(info.captureDate == Fixture.date("2026-05-01T01:05:00Z"))
        #expect(info.latitude == -33.5)
        #expect(info.longitude == -70.25)
    }

    @Test("오프셋이 없으면 절대 시각은 모름, 메타데이터가 없어도 읽힘")
    func readsPartialMetadata() throws {
        let noOffset = root.appending(path: "b.jpg")
        try ImageFixture.write(noOffset, meta: .init(dateTimeOriginal: "2026:05:01 10:05:00"))
        let info = try #require(ImageFiles.readInfo(at: noOffset))
        #expect(info.captureDate == nil)
        #expect(info.captureLocalText == "2026:05:01 10:05:00")

        let bare = root.appending(path: "c.png")
        try ImageFixture.write(bare, type: .png)
        let bareInfo = try #require(ImageFiles.readInfo(at: bare))
        #expect(bareInfo.isWritableFormat)
        #expect(bareInfo.captureLocalText == nil)
        #expect(bareInfo.latitude == nil)
    }

    @Test("이미지가 아닌 파일은 nil")
    func nonImage() throws {
        let url = root.appending(path: "note.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: url)
        #expect(ImageFiles.readInfo(at: url) == nil)
    }

    @Test("쓰기 가능 형식: JPEG/HEIC/PNG/TIFF는 가능, RAW·DNG는 불가")
    func writableTypes() {
        #expect(ImageFiles.isWritable(.jpeg))
        #expect(ImageFiles.isWritable(.heic))
        #expect(ImageFiles.isWritable(.png))
        #expect(ImageFiles.isWritable(.tiff))
        #expect(!ImageFiles.isWritable(UTType(filenameExtension: "dng")!))
        #expect(!ImageFiles.isWritable(UTType(filenameExtension: "cr3")!))
        #expect(!ImageFiles.isWritable(UTType(filenameExtension: "nef")!))
        #expect(!ImageFiles.isWritable(.gif))
    }

    @Test("폴더는 하위까지 이미지 파일만, 숨김 제외, 경로 순, 중복 제거")
    func collectsImages() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "trip/day2"), withIntermediateDirectories: true)
        for path in ["trip/IMG_10.jpg", "trip/IMG_2.HEIC", "trip/day2/IMG_3.jpg", "trip/notes.txt", "trip/.hidden.jpg", "single.png"] {
            try Data().write(to: root.appending(path: path))
        }
        let urls = ImageFiles.collectImages(in: [
            root.appending(path: "trip", directoryHint: .isDirectory),
            root.appending(path: "single.png"),
            root.appending(path: "trip/IMG_2.HEIC"),
        ])
        // 전체 경로 기준 자연 정렬: trip/day2/… 가 trip/IMG_… 보다 앞
        #expect(urls.map(\.lastPathComponent) == ["IMG_3.jpg", "IMG_2.HEIC", "IMG_10.jpg", "single.png"])
    }

    @Test("EXIF 날짜 문자열과 오프셋 변환")
    func exifDateFormat() {
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        let date = Fixture.date("2026-05-01T01:05:00Z")
        #expect(EXIFDateFormat.localText(from: date, timeZone: seoul) == "2026:05:01 10:05:00")
        #expect(EXIFDateFormat.date(fromLocal: "2026:05:01 10:05:00", timeZone: seoul) == date)
        #expect(EXIFDateFormat.date(fromLocal: "2026:05:01 10:05:00", offset: "+0900", timeZone: .gmt) == date)
        #expect(EXIFDateFormat.timeZone(fromOffset: "-03:30")?.secondsFromGMT() == -12_600)
        #expect(EXIFDateFormat.timeZone(fromOffset: "Z") == .gmt)
        #expect(EXIFDateFormat.timeZone(fromOffset: "abc") == nil)
    }
}

@MainActor
@Suite("사진 참조")
final class PhotoStoreTests {
    let root: URL
    let container: ModelContainer
    let store: ProjectStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "PhotoStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = try GeoshopSchema.makeContainer(url: root.appending(path: "Geoshop.store"))
        store = ProjectStore(context: container.mainContext, trackDirectory: root.appending(path: "Tracks"),
                             timeZoneResolver: FixedTimeZoneResolver(TimeZone(identifier: "Asia/Seoul")))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeProject(_ kind: PhotoSourceKind) async throws -> Project {
        let gpx = root.appending(path: "t-\(UUID().uuidString).gpx")
        try Fixture.gpx(tracks: [[[Fixture.pt(37.6, 126.9, time: "2026-05-01T01:00:00Z")]]]).write(to: gpx)
        return try await store.createProject(name: "p", sourceKind: kind, gpxURLs: [gpx])
    }

    @Test("파일·폴더 추가: 기존 정보 기록, 중복·비이미지 건너뜀, RAW는 미지원으로 추가")
    func addFiles() async throws {
        let project = try await makeProject(.files)
        let folder = root.appending(path: "photos", directoryHint: .isDirectory)
        try ImageFixture.write(folder.appending(path: "a.jpg"), meta: .init(dateTimeOriginal: "2026:05:01 10:05:00", offset: "+09:00", latitude: 37.6, longitude: 126.9))
        try ImageFixture.write(folder.appending(path: "b.jpg"), meta: .init(dateTimeOriginal: "2026:05:01 10:06:00"))
        try ImageFixture.write(folder.appending(path: "c.tiff"), type: .tiff)
        // 확장자만 RAW (읽기는 실패) → 건너뜀
        try Data("not really raw".utf8).write(to: folder.appending(path: "d.cr3"))

        let result = try store.addPhotos(fileURLs: [folder], to: project)
        #expect(result.added == 3)
        #expect(result.skipped == ["d.cr3"])

        let again = try store.addPhotos(fileURLs: [folder.appending(path: "a.jpg")], to: project)
        #expect(again == PhotoAddResult(added: 0, duplicates: 1))

        let byName = Dictionary(uniqueKeysWithValues: project.photos.map { ($0.fileName, $0) })
        let a = try #require(byName["a.jpg"])
        #expect(a.originalCaptureDate == Fixture.date("2026-05-01T01:05:00Z"))
        #expect(a.originalLatitude == 37.6)
        #expect(a.bookmarkData != nil)
        let b = try #require(byName["b.jpg"])
        #expect(b.originalCaptureDate == nil)
        #expect(b.originalCaptureLocalText == "2026:05:01 10:06:00")
        #expect(b.originalDate(in: project.timeZone) == Fixture.date("2026-05-01T01:06:00Z"))

        #expect(throws: PhotoImportError.wrongSource) {
            try store.addLibraryPhotos([], to: project)
        }
    }

    @Test("이동한 파일은 북마크로 찾아 경로를 갱신하고, 지운 파일은 찾을 수 없음")
    func resolvesMovedAndMissingFiles() async throws {
        let project = try await makeProject(.files)
        let original = root.appending(path: "in/a.jpg")
        try ImageFixture.write(original)
        try ImageFixture.write(root.appending(path: "in/b.jpg"))
        try store.addPhotos(fileURLs: [root.appending(path: "in", directoryHint: .isDirectory)], to: project)
        let photos = project.photos.sorted { $0.fileName < $1.fileName }

        // a: 같은 볼륨 안에서 이름을 바꿔 이동
        let moved = root.appending(path: "moved/renamed.jpg")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: moved)
        // b: 삭제
        try FileManager.default.removeItem(at: root.appending(path: "in/b.jpg"))

        let resolved = try #require(store.resolveFileURL(for: photos[0]))
        #expect(resolved.lastPathComponent == "renamed.jpg")
        #expect(photos[0].fileName == "renamed.jpg")
        #expect(photos[0].filePath?.hasSuffix("moved/renamed.jpg") == true)

        #expect(store.resolveFileURL(for: photos[1]) == nil)
        #expect(photos[1].status(availability: .missing) == .missing)

        // 다시 연결: 할당은 유지
        photos[1].assignment = Assignment(date: .now, latitude: 1, longitude: 2)
        let replacement = root.appending(path: "other/b2.jpg")
        try ImageFixture.write(replacement)
        try store.relink(photos[1], to: replacement, in: project)
        #expect(store.resolveFileURL(for: photos[1])?.lastPathComponent == "b2.jpg")
        #expect(photos[1].assignment != nil)

        // 이미 있는 파일로 다시 연결은 거부
        #expect(throws: PhotoImportError.duplicate(fileName: "renamed.jpg")) {
            try store.relink(photos[1], to: moved, in: project)
        }
    }

    @Test("보관함 사진 추가·중복·제거, 재실행 후 복원")
    func libraryPhotos() async throws {
        let project = try await makeProject(.photoLibrary)
        let inputs = [
            LibraryPhotoInput(identifier: "A/L0/001", fileName: "IMG_0001.HEIC", creationDate: Fixture.date("2026-05-01T01:00:00Z"), latitude: nil, longitude: nil),
            LibraryPhotoInput(identifier: "B/L0/001", fileName: "IMG_0002.HEIC", creationDate: nil, latitude: 37, longitude: 127),
        ]
        #expect(try store.addLibraryPhotos(inputs, to: project) == PhotoAddResult(added: 2))
        #expect(try store.addLibraryPhotos([inputs[0]], to: project) == PhotoAddResult(added: 0, duplicates: 1))
        #expect(throws: PhotoImportError.wrongSource) { try store.addPhotos(fileURLs: [], to: project) }

        let second = try #require(project.photos.first { $0.assetIdentifier == "B/L0/001" })
        second.assignment = Assignment(date: Fixture.date("2026-05-01T02:00:00Z"), latitude: 1, longitude: 2, altitude: 30)
        try store.removePhotos([project.photos.first { $0.assetIdentifier == "A/L0/001" }!], from: project)

        let reopened = try GeoshopSchema.makeContainer(url: root.appending(path: "Geoshop.store"))
        let photos = try reopened.mainContext.fetch(FetchDescriptor<PhotoRef>())
        #expect(photos.count == 1)
        #expect(photos[0].assetIdentifier == "B/L0/001")
        #expect(photos[0].assignment == Assignment(date: Fixture.date("2026-05-01T02:00:00Z"), latitude: 1, longitude: 2, altitude: 30))
        #expect(photos[0].project?.name == "p")
    }

    @Test("상태 계산 (§4.5)")
    func status() {
        let photo = PhotoRef(fileName: "x.jpg", isWritableFormat: true)
        let a = Assignment(date: .now, latitude: 1, longitude: 2)
        #expect(photo.status(availability: .available) == .unassigned)
        #expect(photo.status(availability: .unknown) == .unassigned)
        photo.assignment = a
        #expect(photo.status(availability: .available) == .pending)
        photo.appliedAssignment = a
        #expect(photo.status(availability: .available) == .applied)
        photo.assignment = Assignment(date: .now, latitude: 3, longitude: 4)
        photo.lastError = "권한 없음"
        #expect(photo.status(availability: .available) == .failed("권한 없음"))
        #expect(photo.status(availability: .notEditable) == .notEditable)
        #expect(photo.status(availability: .missing) == .missing)
        photo.isWritableFormat = false
        #expect(photo.status(availability: .available) == .unsupported)
        #expect(photo.status(availability: .missing) == .missing)
    }
}
