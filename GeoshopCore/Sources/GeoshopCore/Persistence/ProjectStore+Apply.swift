import Foundation

public struct ApplyFailure: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var fileName: String
    public var reason: String

    public init(id: UUID, fileName: String, reason: String) {
        self.id = id
        self.fileName = fileName
        self.reason = reason
    }
}

/// 일괄 적용 결과 (기획서 §4.4).
public struct ApplyResult: Sendable, Equatable {
    public var succeeded = 0
    public var failures: [ApplyFailure] = []
    /// 취소로 처리하지 않은 사진 수.
    public var skippedByCancel = 0

    public init() {}

    public var wasCancelled: Bool { skippedByCancel > 0 }
}

extension ProjectStore {
    /// 적용 대상: 할당이 있고 마지막 적용 값과 다른 사진 (대기·실패).
    public func applyTargets(in project: Project, isBlocked: (PhotoRef) -> Bool = { _ in false }) -> [PhotoRef] {
        project.photos
            .filter { $0.assignment != nil && $0.assignment != $0.appliedAssignment && !isBlocked($0) }
            .sorted { ($0.assignment!.date, $0.fileName) < ($1.assignment!.date, $1.fileName) }
    }

    /// 파일 소스: 사진마다 EXIF를 쓴다. 한 장씩 처리하며 취소하면 남은 사진은 건드리지 않는다.
    /// 실패한 사진은 할당을 그대로 두고 사유를 기록한다 (다시 시도 가능).
    public func applyToFiles(
        _ photos: [PhotoRef],
        timeZone: TimeZone,
        progress: (Int) -> Void = { _ in },
        isCancelled: () -> Bool = { false }
    ) async -> ApplyResult {
        var result = ApplyResult()
        for (index, photo) in photos.enumerated() {
            if isCancelled() {
                result.skippedByCancel = photos.count - index
                break
            }
            defer { progress(index + 1) }
            guard let assignment = photo.assignment else { continue }
            guard let url = resolveFileURL(for: photo) else {
                record(failure: "파일을 찾을 수 없습니다.", for: photo, into: &result)
                continue
            }
            do {
                try await Task.detached(priority: .userInitiated) {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    try EXIFWriter.write(assignment, timeZone: timeZone, to: url)
                }.value
                photo.appliedAssignment = assignment
                photo.lastError = nil
                result.succeeded += 1
            } catch let error as EXIFWriteError {
                record(failure: error.message, for: photo, into: &result)
            } catch {
                record(failure: error.localizedDescription, for: photo, into: &result)
            }
        }
        try? save()
        return result
    }

    /// 보관함 소스 등 외부에서 적용한 결과를 기록한다.
    public func markApplied(_ photos: [PhotoRef]) throws {
        for photo in photos {
            photo.appliedAssignment = photo.assignment
            photo.lastError = nil
        }
        try save()
    }

    public func markFailed(_ photos: [PhotoRef], reason: String) throws {
        for photo in photos { photo.lastError = reason }
        try save()
    }

    private func record(failure reason: String, for photo: PhotoRef, into result: inout ApplyResult) {
        photo.lastError = reason
        result.failures.append(ApplyFailure(id: photo.id, fileName: photo.fileName, reason: reason))
    }
}
