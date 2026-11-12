import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 이미지 파일에서 읽은 기존 촬영 정보와 형식.
public struct ImageFileInfo: Sendable, Equatable {
    public var typeIdentifier: String?
    /// 이 앱이 메타데이터를 쓸 수 있는 형식 (§4.2: JPEG, HEIC/HEIF, PNG, TIFF. RAW·DNG 제외).
    public var isWritableFormat: Bool
    /// EXIF `DateTimeOriginal`(없으면 `DateTimeDigitized`) 원문.
    public var captureLocalText: String?
    /// EXIF `OffsetTimeOriginal`(없으면 `OffsetTimeDigitized`).
    public var captureOffset: String?
    public var latitude: Double?
    public var longitude: Double?

    /// 오프셋이 있으면 절대 시각.
    public var captureDate: Date? {
        guard let captureLocalText, let captureOffset,
              let zone = EXIFDateFormat.timeZone(fromOffset: captureOffset) else { return nil }
        return EXIFDateFormat.date(fromLocal: captureLocalText, timeZone: zone)
    }
}

public enum ImageFiles {
    /// 쓰기 가능한 형식인지. RAW(DNG 포함)는 TIFF 기반이어도 제외.
    public static func isWritable(_ type: UTType) -> Bool {
        if type.conforms(to: .rawImage) { return false }
        return [UTType.jpeg, .heic, .heif, .png, .tiff].contains { type.conforms(to: $0) }
    }

    /// 이미지 파일의 기존 메타데이터를 읽는다. 이미지가 아니면 nil.
    public static func readInfo(at url: URL) -> ImageFileInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let typeID = CGImageSourceGetType(source) as String?
        let type = typeID.flatMap(UTType.init) ?? UTType(filenameExtension: url.pathExtension)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        var info = ImageFileInfo(typeIdentifier: typeID, isWritableFormat: type.map(isWritable) ?? false)
        info.captureLocalText = (exif[kCGImagePropertyExifDateTimeOriginal] ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String
        info.captureOffset = (exif[kCGImagePropertyExifOffsetTimeOriginal] ?? exif[kCGImagePropertyExifOffsetTimeDigitized]) as? String

        if let lat = number(gps[kCGImagePropertyGPSLatitude]), let lon = number(gps[kCGImagePropertyGPSLongitude]) {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
            info.latitude = latRef == "S" ? -abs(lat) : lat
            info.longitude = lonRef == "W" ? -abs(lon) : lon
        }
        return info
    }

    /// 고른 파일·폴더에서 이미지 파일을 모은다. 폴더는 하위까지 뒤지고 숨김 파일·패키지 내부는 건너뛴다.
    /// 확장자 기준으로 이미지(UTType.image)인 것만. 결과는 경로 순, 중복 없음.
    public static func collectImages(in urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        func add(_ url: URL) {
            let key = url.standardizedFileURL.path
            guard isImageFile(url), seen.insert(key).inserted else { return }
            result.append(url)
        }
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]))
                .map { $0.isDirectory == true && $0.isPackage != true } ?? false
            guard isDirectory else { add(url); continue }
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var found: [URL] = []
            for case let child as URL in enumerator
            where (try? child.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                found.append(child)
            }
            found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            found.forEach(add)
        }
        return result
    }

    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? Double)
    }
}
