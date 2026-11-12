import GeoshopCore
import SwiftData
import SwiftUI

@main struct MyApp: App {
    /// 저장소를 열지 못하면 앱을 죽이지 않고 오류 화면을 보여 준다.
    private let storage: Result<(container: ModelContainer, store: ProjectStore), Error>

    init() {
        #if DEBUG
        if DemoData.isEnabled {
            let container = try! GeoshopSchema.makeContainer(inMemory: true)
            let store = ProjectStore(
                context: container.mainContext,
                trackDirectory: FileManager.default.temporaryDirectory.appending(path: "GeoshopDemoTracks")
            )
            storage = .success((container, store))
            Task { await DemoData.seed(store) }
            return
        }
        #endif
        do {
            let container = try GeoshopSchema.makeContainer()
            storage = .success((container, ProjectStore(context: container.mainContext, trackDirectory: ProjectStore.defaultTrackDirectory)))
        } catch {
            storage = .failure(error)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch storage {
                case .success(let storage):
                    ContentView()
                        .environment(\.projectStore, storage.store)
                        .modelContainer(storage.container)
                case .failure(let error):
                    StoreErrorView(error: error)
                }
            }
            .frame(minWidth: 1100, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .help) { HelpCommand() }
        }

        Window("Geoshop 도움말", id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 640, height: 720)
    }
}

/// 저장소(SwiftData)를 열 수 없을 때.
private struct StoreErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("프로젝트 저장소를 열 수 없습니다", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("저장된 프로젝트 정보를 읽지 못했습니다. 사진 원본과 GPX 복사본은 지워지지 않았습니다.\n\n\(error.localizedDescription)")
        } actions: {
            Button("저장소 폴더 열기") {
                NSWorkspace.shared.open(URL.applicationSupportDirectory)
            }
            Button("종료") { NSApp.terminate(nil) }
        }
        .padding()
    }
}
