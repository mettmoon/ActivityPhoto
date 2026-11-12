import Foundation
import CoreLocation
import MapKit

/// 좌표 → 시간대 (기획서 D4).
public protocol TimeZoneResolving: Sendable {
    /// 판별할 수 없으면(네트워크 실패 등) nil.
    func timeZone(latitude: Double, longitude: Double) async -> TimeZone?
}

/// MapKit 역지오코딩으로 시간대를 얻는다. 네트워크가 필요하다.
public struct MapKitTimeZoneResolver: TimeZoneResolving {
    public init() {}

    public func timeZone(latitude: Double, longitude: Double) async -> TimeZone? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let items = try await request.mapItems
            return items.lazy.compactMap(\.timeZone).first
        } catch {
            return nil
        }
    }
}

/// 항상 같은 값을 돌려주는 리졸버 (테스트·미리보기용).
public struct FixedTimeZoneResolver: TimeZoneResolving {
    public let result: TimeZone?

    public init(_ result: TimeZone?) {
        self.result = result
    }

    public func timeZone(latitude: Double, longitude: Double) async -> TimeZone? {
        result
    }
}

extension TimeZone {
    /// 주어진 시각에 두 시간대의 UTC 오프셋이 같은지. 이름이 달라도 오프셋이 같으면 같다고 본다.
    public func hasSameOffset(as other: TimeZone, at date: Date) -> Bool {
        secondsFromGMT(for: date) == other.secondsFromGMT(for: date)
    }

    /// "+09:00" 형식. EXIF `OffsetTimeOriginal` 표기와 같다.
    public func offsetString(at date: Date) -> String {
        let seconds = secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        return String(format: "%@%02d:%02d", sign, minutes / 60, minutes % 60)
    }
}
