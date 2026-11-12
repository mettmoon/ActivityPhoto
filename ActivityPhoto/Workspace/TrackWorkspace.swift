import CoreLocation
import GeoshopCore
import Observation

/// 지도와 고도표가 공유하는 상태 (기획서 §4.3 "지도↔고도표 연동").
/// 한쪽에서 마우스를 올린 지점(`hovered`)을 다른 쪽에도 같은 지점으로 표시한다.
@Observable
final class TrackWorkspace {
    enum Source { case map, chart }

    enum ProfileAxis: String, CaseIterable, Identifiable {
        case distance, time
        var id: Self { self }
        var title: String {
            switch self {
            case .distance: "거리"
            case .time: "시간"
            }
        }
    }

    struct MapPath: Identifiable {
        let segmentIndex: Int
        let colorIndex: Int
        let coordinates: [CLLocationCoordinate2D]
        var id: Int { segmentIndex }
    }

    let timeline: TrackTimeline
    let profile: [ProfileSeries]
    let mapPaths: [MapPath]
    let elevationRange: ClosedRange<Double>?
    /// 세그먼트 → 트랙 색 인덱스.
    private let segmentColors: [Int]

    private(set) var hovered: TrackLocation?
    private(set) var hoverSource: Source?
    /// 클릭으로 고정한 지점. M5에서 사진 할당 대상이 된다.
    var pinned: TrackLocation?
    var axis: ProfileAxis = .distance

    /// - Parameter documentColors: `timeline`을 만들 때 넘긴 GPX 순서대로의 색 인덱스.
    init(timeline: TrackTimeline, documentColors: [Int]) {
        self.timeline = timeline
        profile = timeline.elevationProfile()
        elevationRange = timeline.elevationRange
        segmentColors = timeline.segments.map { segment in
            documentColors.indices.contains(segment.documentIndex) ? documentColors[segment.documentIndex] : 0
        }
        mapPaths = timeline.segments.indices.map { index in
            MapPath(
                segmentIndex: index,
                colorIndex: documentColors.indices.contains(timeline.segments[index].documentIndex)
                    ? documentColors[timeline.segments[index].documentIndex] : 0,
                coordinates: timeline.displayPath(segmentIndex: index).map(\.coordinate)
            )
        }
    }

    func colorIndex(forSegment index: Int) -> Int {
        segmentColors.indices.contains(index) ? segmentColors[index] : 0
    }

    func hover(_ location: TrackLocation?, from source: Source) {
        hovered = location
        hoverSource = location == nil ? nil : source
    }

    /// 마우스가 해당 뷰를 벗어났을 때. 다른 뷰가 이미 호버 중이면 건드리지 않는다.
    func endHover(from source: Source) {
        if hoverSource == source || hoverSource == nil {
            hovered = nil
            hoverSource = nil
        }
    }

    /// 클릭: 지금 호버 중인 지점을 고정한다. 트랙 밖이면 고정 해제.
    func pin(_ location: TrackLocation?) {
        pinned = location
    }
}

extension TrackPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension TrackLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
