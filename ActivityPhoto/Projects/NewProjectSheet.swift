import GeoshopCore
import SwiftUI
import UniformTypeIdentifiers

/// 프로젝트 생성 (기획서 §4.1). GPX 1개 이상과 사진 소스 선택이 필수.
struct NewProjectSheet: View {
    var onCreate: (Project) -> Void

    @Environment(\.projectStore) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sourceKind: PhotoSourceKind = .photoLibrary
    @State private var gpxURLs: [URL] = []
    @State private var isImporting = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("이름", text: $name, prompt: Text("비워 두면 GPX 이름 사용"))
                }

                Section {
                    Picker("사진 소스", selection: $sourceKind) {
                        ForEach(PhotoSourceKind.allCases, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Text(sourceKind.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("사진 소스는 프로젝트를 만든 뒤 바꿀 수 없습니다.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    if gpxURLs.isEmpty {
                        Text("선택한 GPX 없음").foregroundStyle(.secondary)
                    }
                    ForEach(gpxURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            Text(url.lastPathComponent)
                            Spacer()
                            Button("제거", systemImage: "minus.circle") {
                                gpxURLs.removeAll { $0 == url }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("GPX 선택…") { isImporting = true }
                } header: {
                    Text("GPX 파일")
                } footer: {
                    Text("시각 정보가 있는 트랙(trk)이 필요합니다. 파일은 앱 안에 복사해 보관합니다.")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if isCreating {
                    ProgressView().controlSize(.small)
                    Text("GPX 확인 및 시간대 판별 중…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("만들기") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(gpxURLs.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.gpx], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls where !gpxURLs.contains(url) { gpxURLs.append(url) }
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func create() {
        guard let store else { return }
        isCreating = true
        errorMessage = nil
        Task {
            defer { isCreating = false }
            do {
                let project = try await store.createProject(name: name, sourceKind: sourceKind, gpxURLs: gpxURLs)
                onCreate(project)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
