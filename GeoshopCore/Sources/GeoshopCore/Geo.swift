import Foundation

enum Geo {
    /// WGS84 평균 반지름 (미터).
    static let earthRadius = 6_371_008.8

    /// 두 좌표 사이 대원 거리 (미터, haversine).
    static func distance(
        latitude1: Double, longitude1: Double,
        latitude2: Double, longitude2: Double
    ) -> Double {
        let phi1 = latitude1 * .pi / 180
        let phi2 = latitude2 * .pi / 180
        let dPhi = (latitude2 - latitude1) * .pi / 180
        let dLambda = (longitude2 - longitude1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    static func distance(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        distance(latitude1: a.latitude, longitude1: a.longitude, latitude2: b.latitude, longitude2: b.longitude)
    }

    /// 기준점 주변의 국소 평면 투영 (등장방형). 수 km 범위의 최근접점 계산용.
    /// 날짜변경선(±180°)을 걸치는 트랙은 고려하지 않는다.
    struct LocalProjection {
        let originLatitude: Double
        let originLongitude: Double
        private let metersPerDegreeLatitude: Double
        private let metersPerDegreeLongitude: Double

        init(latitude: Double, longitude: Double) {
            originLatitude = latitude
            originLongitude = longitude
            metersPerDegreeLatitude = Geo.earthRadius * .pi / 180
            metersPerDegreeLongitude = metersPerDegreeLatitude * cos(latitude * .pi / 180)
        }

        func project(latitude: Double, longitude: Double) -> SIMD2<Double> {
            SIMD2(
                (longitude - originLongitude) * metersPerDegreeLongitude,
                (latitude - originLatitude) * metersPerDegreeLatitude
            )
        }
    }
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}
