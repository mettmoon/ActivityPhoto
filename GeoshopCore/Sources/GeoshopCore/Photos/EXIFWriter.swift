import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum EXIFWriteError: Error, Equatable, Sendable {
    case unreadable
    case unsupportedFormat
    case encodeFailed(String)
    case writeFailed(String)

    public var message: String {
        switch self {
        case .unreadable: "이미지를 읽을 수 없습니다."
        case .unsupportedFormat: "메타데이터를 쓸 수 없는 형식입니다."
        case .encodeFailed(let reason): "메타데이터를 만들지 못했습니다: \(reason)"
        case .writeFailed(let reason): "파일을 쓰지 못했습니다: \(reason)"
        }
    }
}

/// 파일 EXIF에 할당 값을 쓴다 (기획서 §4.4.2).
///
/// - 이미지 데이터는 다시 압축하지 않는다.
///   - JPEG·HEIC: 원본 메타데이터를 복사해 고친 뒤 `CGImageDestinationCopyImageSource`로 메타데이터만 교체.
///   - PNG·TIFF: 무손실 형식이라 속성 사전을 붙여 다시 담아도 픽셀이 같다 (`AddImageFromSource`).
///   ImageIO의 XMP 병합 경로는 형식마다 일부 필드를 빠뜨리거나 고도를 정수로 반올림해서 쓰지 않는다.
/// - 기존 메타데이터는 유지하고 아래 필드만 덮어쓴다.
///   - EXIF `DateTimeOriginal`, `DateTimeDigitized` (D12), `OffsetTimeOriginal`, `OffsetTimeDigitized`
///   - GPS 위도·경도(+Ref), 고도(+Ref; 값이 없으면 기존 고도 제거), `GPSDateStamp`, `GPSTimeStamp` (UTC)
/// - TIFF `DateTime`(수정 시각)과 파일 시스템 생성·수정일은 바꾸지 않는다.
public enum EXIFWriter {
    public static func write(_ assignment: Assignment, timeZone: TimeZone, to url: URL) throws {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let typeID = CGImageSourceGetType(source)
        else { throw EXIFWriteError.unreadable }
        guard let type = UTType(typeID as String), ImageFiles.isWritable(type) else {
            throw EXIFWriteError.unsupportedFormat
        }

        let values = Values(assignment, timeZone: timeZone)
        let output = NSMutableData()
        let count = CGImageSourceGetCount(source)
        guard let destination = CGImageDestinationCreateWithData(output, typeID, count, nil) else {
            throw EXIFWriteError.encodeFailed("출력 생성 실패")
        }

        if type.conforms(to: .png) || type.conforms(to: .tiff) {
            for index in 0..<count {
                let properties = index == 0 ? values.mergedProperties(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)) : nil
                CGImageDestinationAddImageFromSource(destination, source, index, properties as CFDictionary?)
            }
            guard CGImageDestinationFinalize(destination) else { throw EXIFWriteError.encodeFailed("이미지 저장 실패") }
        } else {
            let base = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
            guard let metadata = base.flatMap({ CGImageMetadataCreateMutableCopy($0) }) ?? CGImageMetadataCreateMutable() as CGMutableImageMetadata? else {
                throw EXIFWriteError.encodeFailed("메타데이터 복사 실패")
            }
            values.apply(to: metadata)
            let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: false]
            var error: Unmanaged<CFError>?
            guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
                throw EXIFWriteError.encodeFailed(error?.takeRetainedValue().localizedDescription ?? "알 수 없는 오류")
            }
        }
        try replaceContents(of: url, with: output as Data)
    }

    /// 쓸 값들.
    struct Values {
        let exif: [CFString: Any]
        let gps: [CFString: Any]
        let altitude: Double?
        /// XMP `exif:GPSTimeStamp` (날짜+시각 하나로 저장된다).
        let gpsDateTimeISO: String

        init(_ assignment: Assignment, timeZone: TimeZone) {
            let local = EXIFDateFormat.localText(from: assignment.date, timeZone: timeZone)
            let offset = timeZone.offsetString(at: assignment.date)
            exif = [
                kCGImagePropertyExifDateTimeOriginal: local,
                kCGImagePropertyExifDateTimeDigitized: local,
                kCGImagePropertyExifOffsetTimeOriginal: offset,
                kCGImagePropertyExifOffsetTimeDigitized: offset,
            ]
            let utc = EXIFDateFormat.localText(from: assignment.date, timeZone: .gmt)   // "yyyy:MM:dd HH:mm:ss"
            var gps: [CFString: Any] = [
                kCGImagePropertyGPSLatitude: abs(assignment.latitude),
                kCGImagePropertyGPSLatitudeRef: assignment.latitude < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude: abs(assignment.longitude),
                kCGImagePropertyGPSLongitudeRef: assignment.longitude < 0 ? "W" : "E",
                kCGImagePropertyGPSDateStamp: String(utc.prefix(10)),
                kCGImagePropertyGPSTimeStamp: String(utc.suffix(8)),
            ]
            if let altitude = assignment.altitude {
                gps[kCGImagePropertyGPSAltitude] = abs(altitude)
                gps[kCGImagePropertyGPSAltitudeRef] = altitude < 0 ? 1 : 0
            }
            self.gps = gps
            altitude = assignment.altitude
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.timeZone = .gmt
            gpsDateTimeISO = isoFormatter.string(from: assignment.date)
        }

        /// PNG·TIFF용: 기존 속성 사전에 덮어쓴다.
        func mergedProperties(_ original: CFDictionary?) -> [CFString: Any] {
            let properties = original as? [CFString: Any] ?? [:]
            var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            exif.merge(self.exif) { $1 }
            var gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
            if altitude == nil {
                gps[kCGImagePropertyGPSAltitude] = nil
                gps[kCGImagePropertyGPSAltitudeRef] = nil
            }
            gps.merge(self.gps) { $1 }
            return [kCGImagePropertyExifDictionary: exif, kCGImagePropertyGPSDictionary: gps]
        }

        /// JPEG·HEIC용: 원본 메타데이터 사본을 고친다.
        func apply(to metadata: CGMutableImageMetadata) {
            for (key, value) in exif {
                CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyExifDictionary, key, value as CFTypeRef)
            }
            for key in [kCGImagePropertyGPSLatitude, kCGImagePropertyGPSLatitudeRef, kCGImagePropertyGPSLongitude, kCGImagePropertyGPSLongitudeRef] {
                CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyGPSDictionary, key, gps[key]! as CFTypeRef)
            }
            if let altitude {
                // 소수 고도가 정수로 반올림되지 않도록 유리수로 직접 쓴다.
                let rational = "\(Int((abs(altitude) * 100).rounded()))/100"
                CGImageMetadataSetValueWithPath(metadata, nil, "exif:GPSAltitude" as CFString, rational as CFString)
                CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyGPSDictionary, kCGImagePropertyGPSAltitudeRef, (altitude < 0 ? 1 : 0) as CFNumber)
            } else {
                CGImageMetadataRemoveTagWithPath(metadata, nil, "exif:GPSAltitude" as CFString)
                CGImageMetadataRemoveTagWithPath(metadata, nil, "exif:GPSAltitudeRef" as CFString)
            }
            // GPSDateStamp·GPSTimeStamp는 XMP에서 하나의 날짜-시각으로 저장된다.
            CGImageMetadataSetValueWithPath(metadata, nil, "exif:GPSTimeStamp" as CFString, gpsDateTimeISO as CFString)
        }
    }

    /// 새 내용으로 원본을 바꾼다. 같은 볼륨의 임시 파일로 원자적 교체를 먼저 시도하고,
    /// 샌드박스가 상위 폴더 쓰기를 막으면 완성된 데이터를 원본 자리에 직접 쓴다.
    /// 어느 경우든 이미지 인코딩이 끝난 뒤에만 원본을 건드린다. 파일 생성·수정일은 원래대로 되돌린다.
    static func replaceContents(of url: URL, with data: Data) throws {
        let fileManager = FileManager.default
        let attributes = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]

        var replaced = false
        if let scratch = try? fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true) {
            defer { try? fileManager.removeItem(at: scratch) }
            let temporary = scratch.appending(path: url.lastPathComponent)
            if (try? data.write(to: temporary)) != nil,
               (try? fileManager.replaceItemAt(url, withItemAt: temporary)) != nil {
                replaced = true
            }
        }
        if !replaced {
            do {
                try data.write(to: url)
            } catch {
                throw EXIFWriteError.writeFailed(error.localizedDescription)
            }
        }

        var preserved: [FileAttributeKey: Any] = [:]
        if let created = attributes[.creationDate] { preserved[.creationDate] = created }
        if let modified = attributes[.modificationDate] { preserved[.modificationDate] = modified }
        if let permissions = attributes[.posixPermissions] { preserved[.posixPermissions] = permissions }
        if !preserved.isEmpty { try? fileManager.setAttributes(preserved, ofItemAtPath: url.path) }
    }
}
