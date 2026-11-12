import GeoshopCore
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var selection: Project.ID?
    @State private var isCreating = false
    @State private var pendingDeletion: Project?
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(projects) { project in
                    ProjectRow(project: project)
                        .tag(project.id)
                        .contextMenu {
                            Button("프로젝트 삭제…", role: .destructive) { pendingDeletion = project }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button("새 프로젝트", systemImage: "plus") { isCreating = true }
                        .keyboardShortcut("n")
                }
            }
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("프로젝트 없음", systemImage: "map")
                    } description: {
                        Text("GPX 파일로 새 프로젝트를 만드세요.")
                    } actions: {
                        Button("새 프로젝트") { isCreating = true }
                    }
                }
            }
        } detail: {
            if let project = projects.first(where: { $0.id == selection }) {
                ProjectDetailView(project: project)
                    .id(project.id)
            } else if projects.isEmpty {
                GettingStartedView(onCreate: { isCreating = true }, onHelp: { openWindow(id: HelpView.windowID) })
            } else {
                ContentUnavailableView("프로젝트를 선택하세요", systemImage: "sidebar.left")
            }
        }
        .sheet(isPresented: $isCreating) {
            NewProjectSheet { created in selection = created.id }
        }
        .confirmationDialog(
            "‘\(pendingDeletion?.name ?? "")’ 프로젝트를 삭제할까요?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                guard let project = pendingDeletion else { return }
                if selection == project.id { selection = nil }
                do { try store?.deleteProject(project) } catch { errorMessage = error.localizedDescription }
                pendingDeletion = nil
            }
        } message: {
            let unapplied = pendingDeletion?.photos.filter { $0.assignment != nil && $0.assignment != $0.appliedAssignment }.count ?? 0
            Text("프로젝트에 복사해 둔 GPX와 할당 정보가 삭제됩니다. 사진 원본은 지워지지 않습니다."
                 + (unapplied > 0 ? "\n\n아직 적용하지 않은 할당 \(unapplied)장이 사라집니다." : ""))
        }
        .alert("오류", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if selection == nil { selection = projects.first?.id }
        }
        .onChange(of: projects.first?.id) { _, first in
            if selection == nil { selection = first }
        }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name).lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: project.sourceKind.systemImage)
                if let start = project.startTime {
                    Text(start.formatted(Date.FormatStyle(date: .numeric, time: .omitted, timeZone: project.timeZone)))
                }
                Text("· GPX \(project.tracks.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// 첫 실행: 프로젝트가 하나도 없을 때의 안내.
private struct GettingStartedView: View {
    var onCreate: () -> Void
    var onHelp: () -> Void

    private let steps: [(String, String, String)] = [
        ("point.topleft.down.to.point.bottomright.curvepath", "GPX로 프로젝트 만들기", "활동 기록(GPX)을 넣고 사진 소스(보관함 또는 파일)를 고릅니다."),
        ("photo.on.rectangle.angled", "사진 추가", "고칠 사진을 넣습니다. 원본은 옮기지 않습니다."),
        ("hand.tap", "지도·고도표에서 지점 선택", "사진을 고르고 클릭하면 그 지점의 시각·위치가 할당됩니다."),
        ("square.and.arrow.down.on.square", "일괄 적용", "확인 후 사진에 촬영일시와 위치를 반영합니다."),
    ]

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Image(systemName: "map").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Geoshop").font(.largeTitle.weight(.bold))
                Text("GPX 기록으로 사진의 촬영일시와 위치를 고칩니다.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: step.0)
                            .font(.title2)
                            .frame(width: 32)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(step.1)").font(.headline)
                            Text(step.2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: 420)
            HStack {
                Button("도움말") { onHelp() }
                Button("새 프로젝트…") { onCreate() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .modelContainer(try! GeoshopSchema.makeContainer(inMemory: true))
}
