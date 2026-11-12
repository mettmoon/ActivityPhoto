import GeoshopCore
import Photos
import SwiftUI

/// 일괄 적용 (기획서 §4.4): 확인 → 진행 → 결과.
struct ApplySheet: View {
    let project: Project
    /// 시트를 열 때 정한 대상 (대기·실패, 할당 불가 제외).
    let targets: [PhotoRef]
    var onFinish: () -> Void

    @Environment(\.projectStore) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case confirm
        case running(done: Int)
        case finished(ApplyResult)
    }

    @State private var phase: Phase = .confirm
    @State private var consent = false
    @State private var cancelRequested = false

    private var isFiles: Bool { project.sourceKind == .files }
    private var needsConsent: Bool { isFiles && !project.overwriteConsentGiven }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch phase {
            case .confirm: confirm
            case .running(let done): running(done: done)
            case .finished(let result): finished(result)
            }
        }
        .padding(20)
        .frame(width: 760, height: 520)
        .interactiveDismissDisabled(isRunning)
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    // MARK: - 확인

    private var confirm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("일괄 적용 — \(targets.count)장").font(.title2.weight(.semibold))

            if isFiles {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("원본 파일을 직접 수정하며 되돌릴 수 없습니다.").fontWeight(.semibold)
                        Text("이미지는 다시 압축하지 않고 촬영일시·위치 정보만 바꿉니다. 파일의 생성·수정일은 그대로 둡니다.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("사진 앱 보관함의 촬영일·위치를 바꿉니다.").fontWeight(.semibold)
                        Text("원본 파일은 그대로입니다. 사진 앱이 변경을 허용할지 한 번 묻습니다. ‘수정되지 않은 원본’으로 내보내면 원래 값이 나옵니다.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(.blue)
                }
            }

            Table(targets) {
                TableColumn("사진") { photo in
                    HStack(spacing: 4) {
                        if photo.lastError != nil {
                            Image(systemName: "arrow.clockwise").foregroundStyle(.red).help("이전 실패: \(photo.lastError ?? "")")
                        }
                        Text(photo.fileName).lineLimit(1).truncationMode(.middle)
                    }
                }
                .width(min: 120, ideal: 160)
                TableColumn("기존 촬영일시") { photo in
                    Text(photo.originalDate(in: project.timeZone).map { $0.formatted(in: project.timeZone) } ?? "없음")
                        .foregroundStyle(.secondary)
                }
                TableColumn("새 촬영일시") { photo in
                    Text(photo.assignment.map { $0.date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, timeZone: project.timeZone)) } ?? "")
                        .fontWeight(.medium)
                }
                TableColumn("기존 위치") { photo in
                    Text(coordinate(photo.originalLatitude, photo.originalLongitude)).foregroundStyle(.secondary)
                }
                TableColumn("새 위치") { photo in
                    Text(photo.assignment.map { coordinate($0.latitude, $0.longitude) } ?? "")
                }
            }
            .font(.callout.monospacedDigit())

            HStack {
                if needsConsent {
                    Toggle("원본 파일이 덮어써지며 되돌릴 수 없음을 이해했습니다", isOn: $consent)
                }
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("\(targets.count)장 적용") { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(targets.isEmpty || (needsConsent && !consent))
            }
        }
    }

    // MARK: - 진행

    private func running(done: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            if isFiles {
                ProgressView(value: Double(done), total: Double(max(targets.count, 1))) {
                    Text("파일에 쓰는 중… \(done) / \(targets.count)")
                }
                Button(cancelRequested ? "취소하는 중…" : "취소") { cancelRequested = true }
                    .disabled(cancelRequested)
                Text("취소해도 이미 처리한 사진은 그대로 적용된 상태로 남습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("사진 앱에서 변경을 허용해 주세요…").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 결과

    private func finished(_ result: ApplyResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("적용 결과").font(.title2.weight(.semibold))
            HStack(spacing: 20) {
                Label("성공 \(result.succeeded)장", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if !result.failures.isEmpty {
                    Label("실패 \(result.failures.count)장", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
                if result.wasCancelled {
                    Label("취소로 건너뜀 \(result.skippedByCancel)장", systemImage: "stop.circle").foregroundStyle(.secondary)
                }
            }
            .font(.headline)
            if result.failures.isEmpty {
                Spacer()
            } else {
                Text("실패한 사진은 할당이 그대로 남아 있어 다시 적용할 수 있습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                Table(result.failures) {
                    TableColumn("사진", value: \.fileName).width(min: 120, ideal: 180)
                    TableColumn("사유", value: \.reason)
                }
            }
            HStack {
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - 실행

    private func run() {
        guard let store else { return }
        if needsConsent {
            project.overwriteConsentGiven = true
            try? store.save()
        }
        phase = .running(done: 0)
        Task {
            let result: ApplyResult
            switch project.sourceKind {
            case .files:
                result = await store.applyToFiles(
                    targets,
                    timeZone: project.timeZone,
                    progress: { phase = .running(done: $0) },
                    isCancelled: { cancelRequested }
                )
            case .photoLibrary:
                result = await applyToLibrary(store: store)
            }
            phase = .finished(result)
            onFinish()
        }
    }

    private func applyToLibrary(store: ProjectStore) async -> ApplyResult {
        var result = ApplyResult()
        let library = PhotoLibraryService.shared
        let changes = targets.compactMap { photo -> (identifier: String, assignment: Assignment)? in
            guard let id = photo.assetIdentifier, let assignment = photo.assignment else { return nil }
            return (id, assignment)
        }
        do {
            guard library.hasFullAccess else {
                throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey: "사진 보관함 전체 접근 권한이 없습니다."])
            }
            try await library.apply(changes)
            try store.markApplied(targets)
            result.succeeded = targets.count
        } catch {
            let reason = Self.reason(for: error)
            try? store.markFailed(targets, reason: reason)
            result.failures = targets.map { ApplyFailure(id: $0.id, fileName: $0.fileName, reason: reason) }
        }
        return result
    }

    private static func reason(for error: Error) -> String {
        if let photos = error as? PHPhotosError, photos.code == .userCancelled {
            return "사진 앱에서 변경을 허용하지 않았습니다."
        }
        return error.localizedDescription
    }

    private func coordinate(_ lat: Double?, _ lon: Double?) -> String {
        guard let lat, let lon else { return "없음" }
        return String(format: "%.5f, %.5f", lat, lon)
    }
}
