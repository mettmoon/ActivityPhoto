import GeoshopCore
import SwiftUI

/// 프로젝트 작업 화면 (기획서 §5): 왼쪽 사진 그리드, 오른쪽 위 지도 + 아래 고도표,
/// 맨 오른쪽 인스펙터(프로젝트 정보·GPX).
struct ProjectDetailView: View {
    @Bindable var project: Project

    @Environment(\.projectStore) private var store
    @State private var catalog = PhotoCatalog()
    @State private var workspace: TrackWorkspace?
    @State private var loadError: String?
    @AppStorage("showsInspector") private var showsInspector = true

    /// GPX 구성이 바뀌면 타임라인을 다시 만든다.
    private var trackSignature: [UUID] {
        project.sortedTracks.map(\.id)
    }

    var body: some View {
        HSplitView {
            PhotoGridView(project: project, catalog: catalog)
                .frame(minWidth: 260, idealWidth: 380, maxWidth: 700)
            Group {
                if let workspace {
                    VSplitView {
                        TrackMapView(workspace: workspace, timeZone: project.timeZone)
                            .frame(minHeight: 240, idealHeight: 420)
                        ElevationChartView(workspace: workspace, timeZone: project.timeZone)
                            .frame(minHeight: 160, idealHeight: 220)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        PinnedLocationBar(workspace: workspace, timeZone: project.timeZone)
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
            let workspace = TrackWorkspace(timeline: timeline, documentColors: project.sortedTracks.map(\.colorIndex))
            #if DEBUG
            if DemoData.isEnabled {
                workspace.pin(timeline.location(atDistance: timeline.totalDistance * DemoData.pinnedFraction))
            }
            #endif
            self.workspace = workspace
            loadError = nil
        } catch {
            workspace = nil
            loadError = error.localizedDescription
        }
    }
}

/// 클릭으로 고정한 지점 표시줄. M5에서 이 지점이 사진 할당 대상이 된다.
private struct PinnedLocationBar: View {
    let workspace: TrackWorkspace
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(workspace.pinned == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            if let pinned = workspace.pinned {
                LocationSummaryView(location: pinned, timeZone: timeZone, showsCoordinate: true)
                Spacer()
                Button("선택 해제") { workspace.pin(nil) }
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                Text("지도나 고도표를 클릭해 지점을 선택하세요.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
