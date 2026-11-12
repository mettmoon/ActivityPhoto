import CoreLocation
import GeoshopCore
import MapKit
import SwiftUI

/// GPX 트랙 지도. 마우스를 올리면 가장 가까운 트랙 위 지점에 스냅해 고도표와 공유하고,
/// 클릭하면 그 지점을 고른다. 겹치는 구간이면 후보 팝오버를 띄운다 (기획서 §4.3, D9).
struct TrackMapView: View {
    let workspace: TrackWorkspace
    let timeZone: TimeZone
    let markers: [AssignmentMarker]
    var onSelectLocation: (TrackLocation) -> Void
    var onSelectMarker: (AssignmentMarker) -> Void

    /// 화면상 스냅 반경 (기획서 §4.3: 약 30pt).
    private let snapRadiusPoints: CGFloat = 30

    @State private var position: MapCameraPosition = .automatic
    @AppStorage("mapStyle") private var style: MapStyleChoice = .standard
    @State private var candidates: [SnapCandidate] = []
    @State private var candidateAnchor: UnitPoint = .center

    var body: some View {
        GeometryReader { geometry in
            MapReader { proxy in
                Map(position: $position) {
                    ForEach(workspace.mapPaths) { path in
                        MapPolyline(coordinates: path.coordinates)
                            .stroke(TrackPalette.color(path.colorIndex),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(markers) { marker in
                        Annotation("", coordinate: marker.coordinate, anchor: .center) {
                            MarkerBadge(marker: marker)
                                .onTapGesture { onSelectMarker(marker) }
                                .help("\(marker.photoIDs.count)장 · " + marker.assignment.date.formatted(in: timeZone))
                        }
                        .annotationTitles(.hidden)
                    }
                    if let hovered = workspace.hovered {
                        Annotation("", coordinate: hovered.coordinate, anchor: .center) {
                            Circle()
                                .fill(TrackPalette.color(workspace.colorIndex(forSegment: hovered.segmentIndex)))
                                .stroke(.white, lineWidth: 2)
                                .frame(width: 14, height: 14)
                                .shadow(radius: 2)
                                .allowsHitTesting(false)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(style.mapStyle)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapZoomStepper()
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    guard candidates.isEmpty else { return }
                    switch phase {
                    case .active(let point):
                        workspace.hover(nearestLocation(at: point, proxy: proxy), from: .map)
                    case .ended:
                        workspace.endHover(from: .map)
                    }
                }
                .onTapGesture(coordinateSpace: .local) { point in
                    // 할당 표시를 누른 클릭은 표시 쪽에서 처리한다 (재할당 방지).
                    let hitsMarker = markers.contains { marker in
                        guard let p = proxy.convert(marker.coordinate, to: .local) else { return false }
                        return hypot(p.x - point.x, p.y - point.y) < 14
                    }
                    guard !hitsMarker else { return }
                    let found = snapCandidates(at: point, proxy: proxy)
                    switch found.count {
                    case 0: break
                    case 1: onSelectLocation(found[0].location)
                    default:
                        candidateAnchor = UnitPoint(x: point.x / max(geometry.size.width, 1), y: point.y / max(geometry.size.height, 1))
                        candidates = found.sorted { $0.location.date < $1.location.date }
                    }
                }
                .popover(
                    isPresented: Binding(get: { !candidates.isEmpty }, set: { if !$0 { candidates = [] } }),
                    attachmentAnchor: .point(candidateAnchor),
                    arrowEdge: .bottom
                ) {
                    CandidateList(candidates: candidates, workspace: workspace, timeZone: timeZone) { location in
                        candidates = []
                        onSelectLocation(location)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let hovered = workspace.hovered {
                LocationBadge(location: hovered, timeZone: timeZone)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 8) {
                Picker("지도 형식", selection: $style) {
                    ForEach(MapStyleChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("트랙 전체 보기", systemImage: "arrow.up.left.and.arrow.down.right") { fitTrack() }
                    .labelStyle(.iconOnly)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
        .onAppear { fitTrack() }
    }

    private func radius(at point: CGPoint, proxy: MapProxy) -> (CLLocationCoordinate2D, Double)? {
        guard
            let coordinate = proxy.convert(point, from: .local),
            let edge = proxy.convert(CGPoint(x: point.x + snapRadiusPoints, y: point.y), from: .local)
        else { return nil }
        let meters = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: edge.latitude, longitude: edge.longitude))
        return (coordinate, meters)
    }

    private func nearestLocation(at point: CGPoint, proxy: MapProxy) -> TrackLocation? {
        guard let (coordinate, meters) = radius(at: point, proxy: proxy) else { return nil }
        return workspace.timeline.nearestLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, radius: meters)
    }

    private func snapCandidates(at point: CGPoint, proxy: MapProxy) -> [SnapCandidate] {
        guard let (coordinate, meters) = radius(at: point, proxy: proxy) else { return [] }
        return workspace.timeline.snapCandidates(latitude: coordinate.latitude, longitude: coordinate.longitude, radius: meters)
    }

    private func fitTrack() {
        guard let bounds = workspace.timeline.bounds else { return }
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.maxLatitude, longitude: bounds.minLongitude))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.minLatitude, longitude: bounds.maxLongitude))
        var rect = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        // 포인트 하나짜리 트랙도 보이도록 최소 크기, 가장자리 여백 15%
        let minimumSize = MKMapPointsPerMeterAtLatitude(bounds.minLatitude) * 500
        rect = rect.insetBy(dx: -max(rect.width * 0.15, minimumSize), dy: -max(rect.height * 0.15, minimumSize))
        withAnimation { position = .rect(rect) }
    }
}

/// 겹치는 구간 후보 목록 (D9). 후보에 마우스를 올리면 고도표에 위치를 표시한다.
private struct CandidateList: View {
    let candidates: [SnapCandidate]
    let workspace: TrackWorkspace
    let timeZone: TimeZone
    var onChoose: (TrackLocation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("이 위치를 여러 번 지났습니다. 시각을 고르세요.")
                .font(.callout.weight(.semibold))
                .padding(.bottom, 4)
            ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                Button {
                    onChoose(candidate.location)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(TrackPalette.color(workspace.colorIndex(forSegment: candidate.location.segmentIndex)))
                            .frame(width: 8, height: 8)
                        LocationSummaryView(location: candidate.location, timeZone: timeZone)
                        Spacer(minLength: 12)
                        Text(workspace.trackName(forSegment: candidate.location.segmentIndex))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(workspace.hovered == candidate.location ? Color.accentColor.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .onHover { inside in
                    if inside { workspace.hover(candidate.location, from: .map) }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 300)
    }
}

/// 지도 위 할당 지점 표시. 대기는 주황, 적용됨은 초록, 선택된 사진이 있으면 강조색·크게.
struct MarkerBadge: View {
    let marker: AssignmentMarker

    var body: some View {
        let color: Color = marker.isSelected ? .accentColor : (marker.isPending ? .orange : .green)
        HStack(spacing: 2) {
            Image(systemName: "camera.fill")
            if marker.photoIDs.count > 1 {
                Text("\(marker.photoIDs.count)").monospacedDigit()
            }
        }
        .font(.system(size: marker.isSelected ? 12 : 10, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, marker.isSelected ? 6 : 4)
        .padding(.vertical, marker.isSelected ? 4 : 3)
        .background(color, in: Capsule())
        .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
        .shadow(radius: 2)
    }
}

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard, hybrid, imagery
    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "지도"
        case .hybrid: "하이브리드"
        case .imagery: "위성"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .hybrid: .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .imagery: .imagery(elevation: .realistic)
        }
    }
}
