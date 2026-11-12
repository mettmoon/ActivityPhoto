import GeoshopCore
import SwiftUI
import UniformTypeIdentifiers

/// 프로젝트 정보·시간대·GPX 관리. 상세 화면 오른쪽 인스펙터에 표시한다.
struct ProjectInspector: View {
    @Bindable var project: Project

    @Environment(\.projectStore) private var store
    @State private var isImporting = false
    @State private var isAdding = false
    @State private var isPickingTimeZone = false
    @State private var isResolvingTimeZone = false
    @State private var warnings: [TrackImportWarning] = []
    @State private var errorMessage: String?

    private var referenceDate: Date { project.startTime ?? .now }

    var body: some View {
        Form {
            Section("프로젝트") {
                TextField("이름", text: $project.name)
                    .onSubmit(fixEmptyName)
                    .onDisappear(perform: fixEmptyName)
                LabeledContent("사진 소스") {
                    Label(project.sourceKind.title, systemImage: project.sourceKind.systemImage)
                }
                if let start = project.startTime, let end = project.endTime {
                    LabeledContent("기간") {
                        Text("\(start.formatted(in: project.timeZone)) – \(end.formatted(in: project.timeZone))")
                    }
                }
            }

            Section {
                LabeledContent("시간대") {
                    HStack {
                        if isResolvingTimeZone { ProgressView().controlSize(.small) }
                        Text(project.timeZone.label(at: referenceDate))
                        Text(project.timeZoneIsAuto ? "자동" : "직접 지정")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if project.timeZoneNeedsReview {
                    Label("GPX 위치로 시간대를 확인하지 못해 이 Mac의 시간대를 쓰고 있습니다. 확인해 주세요.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("시간대 변경…") { isPickingTimeZone = true }
                    Button("GPX 위치로 다시 판별") { resolveTimeZone() }
                        .disabled(isResolvingTimeZone)
                }
            } header: {
                Text("시간대")
            } footer: {
                Text("파일 소스는 촬영일시를 이 시간대의 현지 시각으로 기록합니다. 보관함 소스는 표시에만 씁니다.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(project.sortedTracks) { track in
                    TrackRow(track: track, timeZone: project.timeZone)
                        .contextMenu {
                            Button("GPX 제거", role: .destructive) { remove(track) }
                                .disabled(project.tracks.count <= 1)
                        }
                }
                HStack {
                    Button("GPX 추가…") { isImporting = true }
                        .disabled(isAdding)
                    if isAdding { ProgressView().controlSize(.small) }
                }
            } header: {
                Text("GPX (\(project.tracks.count))")
            } footer: {
                Text("마지막 GPX는 제거할 수 없습니다. 제거하려면 우클릭하세요.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.gpx], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): add(urls)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isPickingTimeZone) {
            TimeZonePickerSheet(current: project.timeZone, referenceDate: referenceDate) { zone in
                perform { try store?.setTimeZone(zone, for: project) }
            }
        }
        .alert("다른 시간대의 GPX", isPresented: Binding(get: { !warnings.isEmpty }, set: { if !$0 { warnings = [] } })) {
            Button("확인") {}
        } message: {
            Text(warningMessage)
        }
        .alert("오류", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var warningMessage: String {
        let lines = warnings.map { warning -> String in
            switch warning {
            case .differentTimeZone(let name, let zone):
                "‘\(name)’: \(zone.label(at: referenceDate))"
            }
        }
        return lines.joined(separator: "\n")
            + "\n\n프로젝트 시간대(\(project.timeZone.identifier))와 다릅니다. 파일 소스라면 촬영일시가 프로젝트 시간대로 기록됩니다. 별도 프로젝트로 나누는 것을 권장합니다."
    }

    private func add(_ urls: [URL]) {
        guard let store else { return }
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                warnings = try await store.addTracks(urls, to: project)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ track: TrackFile) {
        perform { try store?.removeTrack(track, from: project) }
    }

    private func resolveTimeZone() {
        guard let store else { return }
        isResolvingTimeZone = true
        Task {
            defer { isResolvingTimeZone = false }
            do { try await store.resetTimeZoneToAutomatic(for: project) } catch { errorMessage = error.localizedDescription }
        }
    }

    /// 이름을 지운 채 두면 목록에서 빈 줄이 되므로 기본 이름을 넣는다.
    private func fixEmptyName() {
        if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            project.name = "이름 없는 프로젝트"
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

private struct TrackRow: View {
    let track: TrackFile
    let timeZone: TimeZone

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Circle()
                .fill(TrackPalette.color(track.colorIndex))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayName)
                Text("\(track.startTime.formatted(in: timeZone)) – \(track.endTime.formatted(in: timeZone))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDistance(track.distance)).monospacedDigit()
                Text("포인트 \(track.pointCount.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(track.originalFileName)
    }
}
