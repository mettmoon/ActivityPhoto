import Foundation

/// GPX `<trkpt>` 하나. 시각이 없는 포인트는 파싱 단계에서 버리므로 `time`은 항상 있다.
public struct TrackPoint: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    /// GPX `<ele>` (미터). 없으면 nil.
    public var elevation: Double?
    /// 절대 시각 (GPX는 UTC 기준).
    public var time: Date

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
    }
}

/// GPX `<trkseg>`. 포인트는 시각 오름차순(같은 시각 허용)이 보장된다.
public struct TrackSegment: Sendable, Hashable {
    public var points: [TrackPoint]

    public init(points: [TrackPoint]) {
        self.points = points
    }
}

/// GPX `<trk>`.
public struct GPXTrack: Sendable, Hashable {
    public var name: String?
    public var segments: [TrackSegment]

    public init(name: String? = nil, segments: [TrackSegment]) {
        self.name = name
        self.segments = segments
    }
}

/// 파싱한 GPX 파일 하나. 시각이 있는 포인트를 최소 1개 가진 트랙만 담긴다.
public struct GPXDocument: Sendable, Hashable {
    /// GPX 1.1 `<metadata><name>` 또는 GPX 1.0 `<gpx><name>`.
    public var name: String?
    public var tracks: [GPXTrack]

    public init(name: String? = nil, tracks: [GPXTrack]) {
        self.name = name
        self.tracks = tracks
    }

    public var allPoints: some Sequence<TrackPoint> {
        tracks.lazy.flatMap(\.segments).flatMap(\.points)
    }

    public var pointCount: Int {
        tracks.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.points.count } }
    }

    public var startTime: Date? {
        allPoints.lazy.map(\.time).min()
    }

    public var endTime: Date? {
        allPoints.lazy.map(\.time).max()
    }

    /// 시각상 가장 이른 포인트. 시간대 판별(§4.1)에 쓴다.
    public var firstPoint: TrackPoint? {
        allPoints.min { $0.time < $1.time }
    }
}
