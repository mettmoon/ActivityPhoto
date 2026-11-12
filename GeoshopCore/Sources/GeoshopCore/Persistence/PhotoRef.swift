import Foundation
import SwiftData

/// 사진에 임시로 기억해 둔 "적용할 시각 + 위치(+고도)" (기획서 §3).
public struct Assignment: Codable, Hashable, Sendable {
    /// 절대 시각 (UTC).
    public var date: Date
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?

    public init(date: Date, latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    public init(_ location: TrackLocation) {
        self.init(date: location.date, latitude: location.latitude, longitude: location.longitude, altitude: location.elevation)
    }
}

/// 프로젝트에 추가한 사진 하나. 원본은 옮기지 않고 참조만 저장한다 (§4.2).
@Model
public final class PhotoRef {
    @Attribute(.unique) public var id: UUID

    /// 보관함 소스: `PHAsset.localIdentifier`.
    public var assetIdentifier: String?
    /// 파일 소스: 보안 범위 북마크 (app-scope).
    public var bookmarkData: Data?
    /// 파일 소스: 마지막으로 확인한 경로. 중복 판정·표시·다시 연결 안내용.
    public var filePath: String?

    public var fileName: String
    /// 이 앱이 메타데이터를 쓸 수 있는 형식인지 (파일 소스: JPEG/HEIC/PNG/TIFF. RAW·DNG는 false).
    public var isWritableFormat: Bool
    public var addedAt: Date

    /// 추가 시점의 기존 촬영일시 (참고용). 절대 시각을 알 수 있을 때만.
    public var originalCaptureDate: Date?
    /// 파일 EXIF에 시간대 오프셋이 없을 때의 현지 시각 문자열 ("yyyy:MM:dd HH:mm:ss").
    public var originalCaptureLocalText: String?
    public var originalLatitude: Double?
    public var originalLongitude: Double?

    /// 임시 할당 (일괄 적용 대기).
    public var assignment: Assignment?
    /// 마지막으로 적용에 성공한 값.
    public var appliedAssignment: Assignment?
    /// 마지막 적용 실패 사유.
    public var lastError: String?

    public var project: Project?

    public init(
        id: UUID = UUID(),
        assetIdentifier: String? = nil,
        bookmarkData: Data? = nil,
        filePath: String? = nil,
        fileName: String,
        isWritableFormat: Bool,
        addedAt: Date = .now,
        originalCaptureDate: Date? = nil,
        originalCaptureLocalText: String? = nil,
        originalLatitude: Double? = nil,
        originalLongitude: Double? = nil
    ) {
        self.id = id
        self.assetIdentifier = assetIdentifier
        self.bookmarkData = bookmarkData
        self.filePath = filePath
        self.fileName = fileName
        self.isWritableFormat = isWritableFormat
        self.addedAt = addedAt
        self.originalCaptureDate = originalCaptureDate
        self.originalCaptureLocalText = originalCaptureLocalText
        self.originalLatitude = originalLatitude
        self.originalLongitude = originalLongitude
    }

    /// 기존 촬영일시. 오프셋 없는 EXIF 현지 시각은 주어진 시간대(프로젝트 시간대)로 해석한다.
    public func originalDate(in timeZone: TimeZone) -> Date? {
        if let originalCaptureDate { return originalCaptureDate }
        guard let text = originalCaptureLocalText else { return nil }
        return EXIFDateFormat.date(fromLocal: text, timeZone: timeZone)
    }

    public var hasOriginalLocation: Bool {
        originalLatitude != nil && originalLongitude != nil
    }
}

/// EXIF 날짜 문자열 처리.
public enum EXIFDateFormat {
    /// "yyyy:MM:dd HH:mm:ss" (+ 선택적 오프셋 "+09:00") → Date.
    public static func date(fromLocal text: String, offset: String? = nil, timeZone: TimeZone) -> Date? {
        let zone = offset.flatMap(timeZone(fromOffset:)) ?? timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Date → 해당 시간대의 "yyyy:MM:dd HH:mm:ss".
    public static func localText(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// "+09:00", "-03:30", "+0900", "Z" → TimeZone.
    public static func timeZone(fromOffset offset: String) -> TimeZone? {
        let s = offset.trimmingCharacters(in: .whitespaces)
        if s == "Z" { return .gmt }
        guard let sign = s.first, sign == "+" || sign == "-" else { return nil }
        let digits = s.dropFirst().filter(\.isNumber)
        guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }
}
