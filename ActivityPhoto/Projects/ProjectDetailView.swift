import GeoshopCore
import SwiftUI

/// 프로젝트 작업 화면 (기획서 §5): 왼쪽 사진 그리드, 오른쪽 위 지도 + 아래 고도표,
/// 맨 오른쪽 인스펙터(프로젝트 정보·GPX).
///
/// 할당 (§4.3): 사진을 고른 뒤 지도나 고도표를 클릭하면 그 지점의 시각·위치·고도가
/// 선택한 모든 사진에 같은 값으로 들어간다 (D5, D11). ⌘Z로 되돌릴 수 있다.
struct ProjectDetailView: View {
    @Bindable var project: Project

    @Environment(\.projectStore) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var catalog = PhotoCatalog()
    @State private var workspace: TrackWorkspace?
    @State private var loadError: String?
    @State private var notice: Notice?
    @AppStorage("showsInspector") private var showsInspector = true

    /// GPX 구성이 바뀌면 타임라인을 다시 만든다.
    private var trackSignature: [UUID] {
        project.sortedTracks.map(\.id)
    }

    var body: some View {
        HSplitView {
            PhotoGridView(project: project, catalog: catalog, onUnassign: unassign)
                .frame(minWidth: 260, idealWidth: 380, maxWidth: 700)
            Group {
                if let workspace {
                    let markers = AssignmentMarker.build(photos: project.photos, selection: catalog.selection, timeline: workspace.timeline)
                    VSplitView {
                        TrackMapView(workspace: workspace, timeZone: project.timeZone, markers: markers,
                                     onSelectLocation: assign, onSelectMarker: select)
                            .frame(minHeight: 240, idealHeight: 420)
                        ElevationChartView(workspace: workspace, timeZone: project.timeZone, markers: markers,
                                           onSelectLocation: assign)
                            .frame(minHeight: 160, idealHeight: 220)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        SelectionBar(project: project, catalog: catalog, notice: notice, onUnassign: unassign)
                    }
                } else if let loadError {
                    ContentUnavailableView("GPX를 불러올 수 없습니다", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    ProgressView()
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(project.name)
        .inspector(isPresented: $showsInspector) {
            ProjectInspector(project: project)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .toolbar {
            ToolbarItem {
                Button("프로젝트 정보", systemImage: "sidebar.trailing") { showsInspector.toggle() }
            }
        }
        .task(id: trackSignature) { load() }
    }

    private func load() {
        guard let store else { return }
        do {
            let timeline = try store.timeline(for: project)
            let tracks = project.sortedTracks
            workspace = TrackWorkspace(timeline: timeline, documentColors: tracks.map(\.colorIndex), documentNames: tracks.map(\.displayName))
            loadError = nil
        } catch {
            workspace = nil
            loadError = error.localizedDescription
        }
    }

    // MARK: - 할당

    private func assign(_ location: TrackLocation) {
        let selected = catalog.selectedPhotos(in: project)
        guard !selected.isEmpty else {
            show(.hint("먼저 사진을 선택하세요. 선택한 사진에 이 지점의 시각과 위치가 할당됩니다."))
            return
        }
        let targets = selected.filter { !catalog.status(of: $0).isBlocked }
        let blocked = selected.count - targets.count
        guard !targets.isEmpty else {
            show(.warning("선택한 사진은 할당할 수 없는 상태입니다 (찾을 수 없음·미지원·편집 불가)."))
            return
        }
        change(name: "할당") { try $0.setAssignment(Assignment(location), for: targets) }
        let time = location.date.formatted(Date.FormatStyle(date: .omitted, time: .standard, timeZone: project.timeZone))
        show(.info("\(targets.count)장에 \(time) 지점을 할당했습니다." + (blocked > 0 ? " 할당할 수 없는 \(blocked)장은 건너뛰었습니다." : "")))
    }

    private func unassign(_ photos: [PhotoRef]) {
        let targets = photos.filter { $0.assignment != nil }
        guard !targets.isEmpty else { return }
        change(name: "할당 해제") { try $0.setAssignment(nil, for: targets) }
        show(.info("\(targets.count)장의 할당을 해제했습니다."))
    }

    /// 지도 위 할당 표시를 클릭하면 그 지점에 할당된 사진들을 선택한다.
    private func select(_ marker: AssignmentMarker) {
        catalog.selection = Set(marker.photoIDs)
    }

    private func change(name: String, _ body: (ProjectStore) throws -> AssignmentSnapshot) {
        guard let store else { return }
        do {
            let snapshot = try body(store)
            AssignmentUndo.register(snapshot, store: store, undoManager: undoManager, name: name)
        } catch {
            show(.warning(error.localizedDescription))
        }
    }

    private func show(_ notice: Notice) {
        self.notice = notice
        let id = notice.id
        Task {
            try? await Task.sleep(for: .seconds(4))
            if self.notice?.id == id { self.notice = nil }
        }
    }
}

/// 할당 변경을 실행 취소/다시 실행에 등록한다.
@MainActor
enum AssignmentUndo {
    static func register(_ snapshot: AssignmentSnapshot, store: ProjectStore, undoManager: UndoManager?, name: String) {
        guard let undoManager, !snapshot.isEmpty else { return }
        nonisolated(unsafe) let snapshot = snapshot
        undoManager.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                // 되돌리면서 반대 방향(다시 실행)을 등록한다.
                guard let reverse = try? store.restore(snapshot) else { return }
                register(reverse, store: store, undoManager: undoManager, name: name)
            }
        }
        undoManager.setActionName(name)
    }
}

struct Notice: Equatable {
    enum Kind { case info, hint, warning }
    let id = UUID()
    let kind: Kind
    let text: String

    static func info(_ text: String) -> Notice { Notice(kind: .info, text: text) }
    static func hint(_ text: String) -> Notice { Notice(kind: .hint, text: text) }
    static func warning(_ text: String) -> Notice { Notice(kind: .warning, text: text) }
}

/// 아래 표시줄: 선택한 사진의 기존 값 / 할당 값 비교 (§5), 알림.
private struct SelectionBar: View {
    let project: Project
    let catalog: PhotoCatalog
    let notice: Notice?
    var onUnassign: ([PhotoRef]) -> Void

    var body: some View {
        let selected = catalog.selectedPhotos(in: project)
        VStack(alignment: .leading, spacing: 6) {
            if let notice {
                Label(notice.text, systemImage: icon(notice.kind))
                    .foregroundStyle(notice.kind == .warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    .font(.callout)
            }
            HStack(alignment: .top, spacing: 12) {
                switch selected.count {
                case 0:
                    Text("사진을 선택한 뒤 지도나 고도표를 클릭하면 그 지점의 시각과 위치가 할당됩니다.")
                        .foregroundStyle(.secondary)
                case 1:
                    Comparison(photo: selected[0], status: catalog.status(of: selected[0]), timeZone: project.timeZone)
                default:
                    summary(selected)
                }
                Spacer()
                if selected.contains(where: { $0.assignment != nil }) {
                    Button("할당 해제") { onUnassign(selected) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(.default, value: notice)
    }

    private func summary(_ photos: [PhotoRef]) -> some View {
        let statuses = photos.map { catalog.status(of: $0) }
        let assigned = photos.filter { $0.assignment != nil }.count
        let blocked = statuses.filter(\.isBlocked).count
        let distinct = Set(photos.compactMap(\.assignment)).count
        var parts = ["\(photos.count)장 선택", "할당됨 \(assigned)"]
        if distinct > 1 { parts.append("서로 다른 지점 \(distinct)곳") }
        if blocked > 0 { parts.append("할당 불가 \(blocked)") }
        return Text(parts.joined(separator: " · ")).foregroundStyle(.secondary)
    }

    private func icon(_ kind: Notice.Kind) -> String {
        switch kind {
        case .info: "checkmark.circle"
        case .hint: "hand.point.up.left"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
}

/// 사진 한 장: 기존 값 → 할당 값.
private struct Comparison: View {
    let photo: PhotoRef
    let status: PhotoStatus
    let timeZone: TimeZone

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text(photo.fileName).font(.callout.weight(.semibold)).lineLimit(1)
                Text("기존").foregroundStyle(.secondary)
                Text("할당").foregroundStyle(.secondary)
            }
            .font(.caption)
            GridRow {
                Text(status.description).font(.caption).foregroundStyle(.secondary)
                Text(photo.originalDate(in: timeZone).map { $0.formatted(in: timeZone) } ?? "없음")
                Text(photo.assignment.map { $0.date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, timeZone: timeZone)) } ?? "—")
                    .fontWeight(photo.assignment == nil ? .regular : .semibold)
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Text(coordinate(photo.originalLatitude, photo.originalLongitude))
                Text(photo.assignment.map { coordinate($0.latitude, $0.longitude) + ($0.altitude.map { String(format: " · %.0f m", $0) } ?? "") } ?? "—")
            }
        }
        .font(.caption.monospacedDigit())
        .textSelection(.enabled)
    }

    private func coordinate(_ lat: Double?, _ lon: Double?) -> String {
        guard let lat, let lon else { return "위치 없음" }
        return String(format: "%.5f, %.5f", lat, lon)
    }
}
