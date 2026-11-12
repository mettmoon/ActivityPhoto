import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import GeoshopCore

/// 압축 손실이 드러나도록 무늬가 있는 이미지 + 기존 메타데이터(렌즈 정보, 옛 촬영일시, 옛 위치).
private func writePatternedImage(_ url: URL, type: UTType) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let size = 64
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    var seed: UInt64 = 42
    for y in 0..<size {
        for x in 0..<size {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = CGFloat((seed >> 33) % 255) / 255
            context.setFillColor(red: v, green: CGFloat(x) / 64, blue: CGFloat(y) / 64, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: "2001:01:01 00:00:00",
            kCGImagePropertyExifLensModel: "Test Lens 35mm",
        ],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 1.0, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 1.0, kCGImagePropertyGPSLongitudeRef: "E",
        ],
    ]
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
}

/// 디코딩한 픽셀 (RGBA8).
private func pixels(_ url: URL) throws -> [UInt8] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buffer
}

private func properties(_ url: URL) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
}

@Suite("EXIF 쓰기")
struct EXIFWriterTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "EXIFWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    /// 2026-05-01 10:05:07 KST, 남·서반구 좌표로 Ref 처리까지 확인.
    let assignment = Assignment(date: Fixture.date("2026-05-01T01:05:07Z"), latitude: -33.4489, longitude: -70.6693, altitude: 612.4)

    @Test("촬영일시·오프셋·GPS를 쓰고, 픽셀·기존 메타데이터·파일 날짜는 그대로", arguments: ["jpg", "heic", "png", "tiff"])
    func writesLosslessly(ext: String) throws {
        let type = try #require(UTType(filenameExtension: ext))
        let url = root.appending(path: "photo.\(ext)")
        try writePatternedImage(url, type: type)
        let oldDate = Fixture.date("2020-02-02T02:02:02Z")
        try FileManager.default.setAttributes([.modificationDate: oldDate, .creationDate: oldDate], ofItemAtPath: url.path)
        let before = try pixels(url)

        try EXIFWriter.write(assignment, timeZone: seoul, to: url)

        // 다시 읽은 값
        let info = try #require(ImageFiles.readInfo(at: url))
        #expect(info.captureLocalText == "2026:05:01 10:05:07")
        #expect(info.captureOffset == "+09:00")
        #expect(info.captureDate == assignment.date)
        #expect(abs(info.latitude! - assignment.latitude) < 1e-6)
        #expect(abs(info.longitude! - assignment.longitude) < 1e-6)

        let props = try properties(url)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeDigitized] as? String == "2026:05:01 10:05:07")
        #expect(exif[kCGImagePropertyExifOffsetTimeDigitized] as? String == "+09:00")
        #expect(exif[kCGImagePropertyExifLensModel] as? String == "Test Lens 35mm")
        #expect(((gps[kCGImagePropertyGPSAltitude] as? NSNumber)?.doubleValue).map { abs($0 - 612.4) < 0.01 } == true)
        #expect((gps[kCGImagePropertyGPSAltitudeRef] as? NSNumber)?.intValue == 0)
        #expect(gps[kCGImagePropertyGPSDateStamp] as? String == "2026:05:01")
        #expect((gps[kCGImagePropertyGPSTimeStamp] as? String)?.hasPrefix("01:05:07") == true)

        // 재압축 없음: 디코딩한 픽셀이 같다
        #expect(try pixels(url) == before)

        // 파일 시스템 날짜 유지
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.modificationDate] as? Date == oldDate)
    }

    @Test("고도가 없으면 고도는 쓰지 않는다, 해수면 아래는 Ref 1")
    func altitudeHandling() throws {
        let url = root.appending(path: "alt.jpg")
        try writePatternedImage(url, type: .jpeg)
        try EXIFWriter.write(Assignment(date: assignment.date, latitude: 10, longitude: 20, altitude: -12), timeZone: seoul, to: url)
        var gps = try properties(url)[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        #expect((gps[kCGImagePropertyGPSAltitudeRef] as? NSNumber)?.intValue == 1)
        #expect((gps[kCGImagePropertyGPSAltitude] as? NSNumber)?.doubleValue == 12)
        #expect(gps[kCGImagePropertyGPSLatitudeRef] as? String == "N")

        let fresh = root.appending(path: "noalt.jpg")
        try writePatternedImage(fresh, type: .jpeg)
        try EXIFWriter.write(Assignment(date: assignment.date, latitude: 10, longitude: 20), timeZone: seoul, to: fresh)
        gps = try properties(fresh)[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        #expect(gps[kCGImagePropertyGPSAltitude] == nil)
    }

    @Test("지원하지 않는 형식(GIF)은 거부하고 파일을 건드리지 않는다")
    func rejectsUnsupported() throws {
        let url = root.appending(path: "anim.gif")
        try writePatternedImage(url, type: .gif)
        let before = try Data(contentsOf: url)
        #expect(throws: EXIFWriteError.unsupportedFormat) {
            try EXIFWriter.write(assignment, timeZone: seoul, to: url)
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("서머타임 시간대는 그 날짜의 오프셋으로 기록")
    func daylightSaving() throws {
        let url = root.appending(path: "dst.jpg")
        try writePatternedImage(url, type: .jpeg)
        let paris = TimeZone(identifier: "Europe/Paris")!
        try EXIFWriter.write(Assignment(date: Fixture.date("2026-07-01T10:00:00Z"), latitude: 48.85, longitude: 2.35), timeZone: paris, to: url)
        let info = try #require(ImageFiles.readInfo(at: url))
        #expect(info.captureLocalText == "2026:07:01 12:00:00")
        #expect(info.captureOffset == "+02:00")
    }
}

@MainActor
@Suite("일괄 적용")
final class ApplyStoreTests {
    let root: URL
    let container: ModelContainer
    let store: ProjectStore
    var project: Project!

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ApplyStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = try GeoshopSchema.makeContainer(inMemory: true)
        store = ProjectStore(context: container.mainContext, trackDirectory: root.appending(path: "Tracks"))
        project = Project(name: "p", sourceKind: .files, timeZoneID: "Asia/Seoul")
        container.mainContext.insert(project)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func addPhotos(_ names: [String]) throws -> [PhotoRef] {
        for name in names {
            try writePatternedImage(root.appending(path: "in/\(name)"), type: UTType(filenameExtension: (name as NSString).pathExtension)!)
        }
        try store.addPhotos(fileURLs: names.map { root.appending(path: "in/\($0)") }, to: project)
        return names.map { name in project.photos.first { $0.fileName == name }! }
    }

    @Test("성공은 적용됨, 파일이 없으면 실패로 남기고 다시 시도할 수 있다")
    func appliesAndRecordsFailures() async throws {
        let photos = try addPhotos(["a.jpg", "b.jpg", "c.png"])
        let here = Assignment(date: Fixture.date("2026-05-01T01:00:00Z"), latitude: 37.6, longitude: 126.9, altitude: 300)
        try store.setAssignment(here, for: photos)
        try FileManager.default.removeItem(at: root.appending(path: "in/b.jpg"))

        let targets = store.applyTargets(in: project)
        #expect(targets.count == 3)
        var progressed: [Int] = []
        let result = await store.applyToFiles(targets, timeZone: project.timeZone, progress: { progressed.append($0) })

        #expect(result.succeeded == 2)
        #expect(result.failures.map(\.fileName) == ["b.jpg"])
        #expect(result.failures.first?.reason == "파일을 찾을 수 없습니다.")
        #expect(progressed == [1, 2, 3])
        #expect(photos[0].status(availability: .available) == .applied)
        #expect(photos[1].status(availability: .available) == .failed("파일을 찾을 수 없습니다."))
        #expect(ImageFiles.readInfo(at: root.appending(path: "in/c.png"))?.captureDate == here.date)

        // 실패한 사진만 다시 대상이 된다
        #expect(store.applyTargets(in: project).map(\.fileName) == ["b.jpg"])
        #expect(store.applyTargets(in: project, isBlocked: { $0.fileName == "b.jpg" }).isEmpty)
    }

    @Test("취소하면 남은 사진은 건드리지 않는다")
    func cancellation() async throws {
        let photos = try addPhotos(["a.jpg", "b.jpg", "c.jpg"])
        try store.setAssignment(Assignment(date: Fixture.date("2026-05-01T01:00:00Z"), latitude: 1, longitude: 2), for: photos)
        var done = 0
        let result = await store.applyToFiles(
            store.applyTargets(in: project), timeZone: project.timeZone,
            progress: { done = $0 }, isCancelled: { done >= 1 }
        )
        #expect(result.succeeded == 1)
        #expect(result.skippedByCancel == 2)
        #expect(result.wasCancelled)
        #expect(photos.filter { $0.status(availability: .available) == .applied }.count == 1)
        #expect(ImageFiles.readInfo(at: root.appending(path: "in/c.jpg"))?.captureLocalText == "2001:01:01 00:00:00")
    }

    @Test("외부(보관함) 적용 결과 기록")
    func markResults() throws {
        let photo = PhotoRef(assetIdentifier: "x", fileName: "x.heic", isWritableFormat: true)
        project.photos.append(photo)
        photo.assignment = Assignment(date: .now, latitude: 1, longitude: 2)
        try store.markFailed([photo], reason: "사용자가 거부함")
        #expect(photo.status(availability: .available) == .failed("사용자가 거부함"))
        try store.markApplied([photo])
        #expect(photo.status(availability: .available) == .applied)
        #expect(photo.lastError == nil)
    }
}
