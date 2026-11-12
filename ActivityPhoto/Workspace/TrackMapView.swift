import CoreLocation
import GeoshopCore
import MapKit
import SwiftUI

/// GPX 트랙 지도. 마우스를 올리면 가장 가까운 트랙 위 지점에 스냅해 고도표와 공유한다.
struct TrackMapView: View {
    let workspace: TrackWorkspace
    let timeZone: TimeZone

    /// 화면상 스냅 반경 (기획서 §4.3: 약 30pt).
    private let snapRadiusPoints: CGFloat = 30

    @State private var position: MapCameraPosition = .automatic
    @AppStorage("mapStyle") private var style: MapStyleChoice = .standard

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                ForEach(workspace.mapPaths) { path in
                    MapPolyline(coordinates: path.coordinates)
                        .stroke(TrackPalette.color(path.colorIndex),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if let pinned = workspace.pinned {
                    Annotation("선택 지점", coordinate: pinned.coordinate, anchor: .bottom) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .red)
                            .shadow(radius: 2)
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
                switch phase {
                case .active(let point):
                    workspace.hover(nearestLocation(at: point, proxy: proxy), from: .map)
                case .ended:
                    workspace.endHover(from: .map)
                }
            }
            .onTapGesture(coordinateSpace: .local) { point in
                workspace.pin(nearestLocation(at: point, proxy: proxy))
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

    private func nearestLocation(at point: CGPoint, proxy: MapProxy) -> TrackLocation? {
        guard
            let coordinate = proxy.convert(point, from: .local),
            let edge = proxy.convert(CGPoint(x: point.x + snapRadiusPoints, y: point.y), from: .local)
        else { return nil }
        let radius = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: edge.latitude, longitude: edge.longitude))
        return workspace.timeline.nearestLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, radius: radius)
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
