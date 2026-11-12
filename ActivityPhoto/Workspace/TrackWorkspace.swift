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
    /// 세그먼트 → 트랙(GPX) 이름.
    private let segmentNames: [String]

    private(set) var hovered: TrackLocation?
    private(set) var hoverSource: Source?
    var axis: ProfileAxis = .distance

    /// - Parameters:
    ///   - documentColors: `timeline`을 만들 때 넘긴 GPX 순서대로의 색 인덱스.
    ///   - documentNames: 같은 순서의 GPX 표시 이름.
    init(timeline: TrackTimeline, documentColors: [Int], documentNames: [String]) {
        self.timeline = timeline
        profile = timeline.elevationProfile()
        elevationRange = timeline.elevationRange
        segmentColors = timeline.segments.map { documentColors.indices.contains($0.documentIndex) ? documentColors[$0.documentIndex] : 0 }
        segmentNames = timeline.segments.map { segment in
            documentNames.indices.contains(segment.documentIndex) ? documentNames[segment.documentIndex] : (segment.trackName ?? "트랙")
        }
        let colors = segmentColors
        mapPaths = timeline.segments.indices.map { index in
            MapPath(
                segmentIndex: index,
                colorIndex: colors[index],
                coordinates: timeline.displayPath(segmentIndex: index).map(\.coordinate)
            )
        }
    }

    func colorIndex(forSegment index: Int) -> Int {
        segmentColors.indices.contains(index) ? segmentColors[index] : 0
    }

    func trackName(forSegment index: Int) -> String {
        segmentNames.indices.contains(index) ? segmentNames[index] : "트랙"
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
}

/// 지도·고도표에 그리는 할당 지점. 같은 값을 할당받은 사진들을 하나로 묶는다.
struct AssignmentMarker: Identifiable {
    let assignment: Assignment
    /// 타임라인 위 지점 (고도표 위치용). 할당 후 GPX를 지웠다면 nil.
    let location: TrackLocation?
    let photoIDs: [UUID]
    let isSelected: Bool
    /// 아직 적용 전인 사진이 하나라도 있음.
    let isPending: Bool

    var id: Assignment { assignment }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: assignment.latitude, longitude: assignment.longitude)
    }

    static func build(photos: [PhotoRef], selection: Set<UUID>, timeline: TrackTimeline) -> [AssignmentMarker] {
        let groups = Dictionary(grouping: photos.filter { $0.assignment != nil }) { $0.assignment! }
        return groups.map { assignment, photos in
            AssignmentMarker(
                assignment: assignment,
                location: timeline.location(at: assignment.date),
                photoIDs: photos.map(\.id),
                isSelected: photos.contains { selection.contains($0.id) },
                isPending: photos.contains { $0.appliedAssignment != assignment }
            )
        }
        // 선택된 것을 위에 그린다.
        .sorted { ($0.isSelected ? 1 : 0, $0.assignment.date) < ($1.isSelected ? 1 : 0, $1.assignment.date) }
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
