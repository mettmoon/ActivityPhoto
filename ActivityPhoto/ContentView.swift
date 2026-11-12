import GeoshopCore
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.projectStore) private var store
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
            Text("프로젝트에 복사해 둔 GPX와 할당 정보가 삭제됩니다. 사진 원본은 지워지지 않습니다.")
        }
        .alert("오류", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if selection == nil { selection = projects.first?.id }
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

#Preview {
    ContentView()
        .modelContainer(try! GeoshopSchema.makeContainer(inMemory: true))
}
