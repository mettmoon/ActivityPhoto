import GeoshopCore
import SwiftData
import SwiftUI

@main struct MyApp: App {
    private let container: ModelContainer
    private let store: ProjectStore

    init() {
        #if DEBUG
        if DemoData.isEnabled {
            container = try! GeoshopSchema.makeContainer(inMemory: true)
            store = ProjectStore(
                context: container.mainContext,
                trackDirectory: FileManager.default.temporaryDirectory.appending(path: "GeoshopDemoTracks")
            )
            let store = store
            Task { await DemoData.seed(store) }
            return
        }
        #endif
        do {
            container = try GeoshopSchema.makeContainer()
        } catch {
            fatalError("프로젝트 저장소를 열 수 없습니다: \(error)")
        }
        store = ProjectStore(context: container.mainContext, trackDirectory: ProjectStore.defaultTrackDirectory)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 600)
                .environment(\.projectStore, store)
        }
        .modelContainer(container)
    }
}
