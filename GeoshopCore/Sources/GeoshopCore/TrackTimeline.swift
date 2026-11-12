import Foundation

/// 트랙 위의 한 지점. 두 트랙 포인트 사이는 선형 보간한 값이다.
public struct TrackLocation: Sendable, Hashable {
    public var date: Date
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double?
    /// 타임라인 시작부터의 누적 거리 (미터). 세그먼트 사이 공백은 0으로 친다.
    public var distance: Double
    /// `TrackTimeline.segments`의 인덱스.
    public var segmentIndex: Int

    public init(
        date: Date, latitude: Double, longitude: Double, elevation: Double?,
        distance: Double, segmentIndex: Int
    ) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.distance = distance
        self.segmentIndex = segmentIndex
    }
}

/// 지도 클릭 지점 근처의 트랙 위 후보 (기획서 D9).
public struct SnapCandidate: Sendable, Hashable {
    public var location: TrackLocation
    /// 클릭 지점에서 후보까지 거리 (미터).
    public var offset: Double
}

/// 타임라인을 이루는 세그먼트 하나 (GPX `<trkseg>` 하나에 대응).
public struct TimelineSegment: Sendable, Hashable {
    /// 프로젝트에 넣은 GPX 파일 순서 (`TrackTimeline.init(documents:)`의 인덱스).
    public let documentIndex: Int
    public let trackName: String?
    public let points: [TrackPoint]
    /// `points`와 같은 개수. 타임라인 전체 기준 누적 거리 (미터).
    public let cumulativeDistances: [Double]

    public var startTime: Date { points[0].time }
    public var endTime: Date { points[points.count - 1].time }
    public var startDistance: Double { cumulativeDistances[0] }
    public var endDistance: Double { cumulativeDistances[cumulativeDistances.count - 1] }
}

/// 프로젝트의 모든 GPX를 시각 순으로 이어 붙인 타임라인.
///
/// - 세그먼트는 시작 시각 순으로 정렬한다. 서로 다른 GPX의 세그먼트가 시간상 겹칠 수도 있다.
/// - 누적 거리(고도표 x축)는 세그먼트 안에서만 늘어나고, 세그먼트 사이 공백(이동 거리)은 더하지 않는다.
public struct TrackTimeline: Sendable, Hashable {
    public let segments: [TimelineSegment]

    public init(documents: [GPXDocument]) {
        var raw: [(documentIndex: Int, trackName: String?, points: [TrackPoint])] = []
        for (documentIndex, document) in documents.enumerated() {
            for track in document.tracks {
                for segment in track.segments where !segment.points.isEmpty {
                    raw.append((documentIndex, track.name, segment.points))
                }
            }
        }
        // 안정 정렬: 시작 시각이 같으면 입력 순서 유지.
        let ordered = raw.enumerated().sorted {
            ($0.element.points[0].time, $0.offset) < ($1.element.points[0].time, $1.offset)
        }.map(\.element)

        var distance = 0.0
        var built: [TimelineSegment] = []
        built.reserveCapacity(ordered.count)
        for item in ordered {
            var cumulative: [Double] = []
            cumulative.reserveCapacity(item.points.count)
            for (i, point) in item.points.enumerated() {
                if i > 0 { distance += Geo.distance(item.points[i - 1], point) }
                cumulative.append(distance)
            }
            built.append(TimelineSegment(
                documentIndex: item.documentIndex,
                trackName: item.trackName,
                points: item.points,
                cumulativeDistances: cumulative
            ))
        }
        segments = built
    }

    public var isEmpty: Bool { segments.isEmpty }
    public var totalDistance: Double { segments.last?.endDistance ?? 0 }
    public var startTime: Date? { segments.lazy.map(\.startTime).min() }
    public var endTime: Date? { segments.lazy.map(\.endTime).max() }

    // MARK: - 시각 → 지점

    /// 주어진 시각의 트랙 위 지점. 기록이 없는 공백 시각이면 nil.
    /// 여러 세그먼트가 그 시각을 포함하면 정렬상 앞의 세그먼트를 쓴다.
    public func location(at date: Date) -> TrackLocation? {
        for (segmentIndex, segment) in segments.enumerated()
        where segment.startTime <= date && date <= segment.endTime {
            let points = segment.points
            // date 이하인 마지막 포인트를 찾는다.
            let upper = upperBound(count: points.count) { points[$0].time <= date }
            let i = max(upper - 1, 0)
            guard i < points.count - 1 else {
                return location(segmentIndex: segmentIndex, index: i, fraction: 0)
            }
            let t0 = points[i].time, t1 = points[i + 1].time
            let span = t1.timeIntervalSince(t0)
            let fraction = span > 0 ? date.timeIntervalSince(t0) / span : 0
            return location(segmentIndex: segmentIndex, index: i, fraction: fraction)
        }
        return nil
    }

    // MARK: - 누적 거리 → 지점

    /// 누적 거리(고도표 거리 축)의 트랙 위 지점. 범위 밖이면 양 끝으로 고정한다.
    /// 세그먼트 경계처럼 같은 거리에 여러 지점이 있으면 시각상 앞의 것을 쓴다.
    public func location(atDistance distance: Double) -> TrackLocation? {
        guard !segments.isEmpty else { return nil }
        let d = min(max(distance, 0), totalDistance)
        let segmentIndex = segments.firstIndex { d <= $0.endDistance } ?? segments.count - 1
        let cumulative = segments[segmentIndex].cumulativeDistances
        let upper = upperBound(count: cumulative.count) { cumulative[$0] <= d }
        var i = max(upper - 1, 0)
        // 같은 누적 거리가 이어지면(정지 구간) 가장 이른 포인트로.
        while i > 0 && cumulative[i - 1] == cumulative[i] && cumulative[i] == d { i -= 1 }
        guard i < cumulative.count - 1 else {
            return location(segmentIndex: segmentIndex, index: i, fraction: 0)
        }
        let span = cumulative[i + 1] - cumulative[i]
        let fraction = span > 0 ? (d - cumulative[i]) / span : 0
        return location(segmentIndex: segmentIndex, index: i, fraction: fraction)
    }

    // MARK: - 지도 클릭 → 후보 지점

    /// 클릭한 좌표에서 `radius`(미터) 안에 있는 트랙 위 후보 지점들 (기획서 §4.3, D9).
    ///
    /// 반경 안에 든 트랙 조각마다 최근접점을 구한 뒤 시각 순으로 늘어놓고,
    /// 이웃 후보와 시각 차이가 `minimumTimeSeparation` 이하면 같은 통과로 묶는다.
    /// 묶음마다 가장 가까운 점 하나를 남기고, 클릭 지점에 가까운 순서로 돌려준다.
    /// 결과가 2개 이상이면 UI는 후보 팝오버를, 1개면 바로 할당을 한다.
    public func snapCandidates(
        latitude: Double,
        longitude: Double,
        radius: Double,
        minimumTimeSeparation: TimeInterval = 300
    ) -> [SnapCandidate] {
        let projection = Geo.LocalProjection(latitude: latitude, longitude: longitude)
        var hits: [SnapCandidate] = []

        for (segmentIndex, segment) in segments.enumerated() {
            let projected = segment.points.map { projection.project(latitude: $0.latitude, longitude: $0.longitude) }
            if projected.count == 1 {
                let offset = (projected[0] * projected[0]).sum().squareRoot()
                if offset <= radius {
                    hits.append(SnapCandidate(
                        location: location(segmentIndex: segmentIndex, index: 0, fraction: 0),
                        offset: offset
                    ))
                }
                continue
            }
            for i in 0..<(projected.count - 1) {
                let a = projected[i], b = projected[i + 1]
                let ab = b - a
                let lengthSquared = (ab * ab).sum()
                let t = lengthSquared > 0 ? min(max((-a * ab).sum() / lengthSquared, 0), 1) : 0
                let closest = a + ab * t
                let offset = (closest * closest).sum().squareRoot()
                guard offset <= radius else { continue }
                hits.append(SnapCandidate(
                    location: location(segmentIndex: segmentIndex, index: i, fraction: t),
                    offset: offset
                ))
            }
        }

        hits.sort { $0.location.date < $1.location.date }
        var result: [SnapCandidate] = []
        var clusterBest: SnapCandidate?
        var previousDate: Date?
        for hit in hits {
            if let previous = previousDate,
               hit.location.date.timeIntervalSince(previous) > minimumTimeSeparation,
               let best = clusterBest {
                result.append(best)
                clusterBest = nil
            }
            if clusterBest == nil || hit.offset < clusterBest!.offset {
                clusterBest = hit
            }
            previousDate = hit.location.date
        }
        if let best = clusterBest { result.append(best) }
        return result.sorted { $0.offset < $1.offset }
    }

    // MARK: - 보간

    /// `points[index]`와 `points[index + 1]` 사이를 `fraction`(0...1)만큼 보간한 지점.
    func location(segmentIndex: Int, index: Int, fraction: Double) -> TrackLocation {
        let segment = segments[segmentIndex]
        let a = segment.points[index]
        guard fraction > 0, index + 1 < segment.points.count else {
            return TrackLocation(
                date: a.time, latitude: a.latitude, longitude: a.longitude, elevation: a.elevation,
                distance: segment.cumulativeDistances[index], segmentIndex: segmentIndex
            )
        }
        let b = segment.points[index + 1]
        let t = min(fraction, 1)
        let elevation: Double? = switch (a.elevation, b.elevation) {
        case let (ea?, eb?): lerp(ea, eb, t)
        case let (ea?, nil): ea
        case let (nil, eb?): eb
        case (nil, nil): nil
        }
        return TrackLocation(
            date: a.time.addingTimeInterval(b.time.timeIntervalSince(a.time) * t),
            latitude: lerp(a.latitude, b.latitude, t),
            longitude: lerp(a.longitude, b.longitude, t),
            elevation: elevation,
            distance: lerp(segment.cumulativeDistances[index], segment.cumulativeDistances[index + 1], t),
            segmentIndex: segmentIndex
        )
    }
}

/// `isBelow`가 true인 앞쪽 구간의 끝 인덱스 (이진 탐색). `isBelow`는 단조여야 한다.
private func upperBound(count: Int, _ isBelow: (Int) -> Bool) -> Int {
    var low = 0, high = count
    while low < high {
        let mid = (low + high) / 2
        if isBelow(mid) { low = mid + 1 } else { high = mid }
    }
    return low
}
