import Foundation

/// 원본 참조를 확인한 결과 (실행 중에만 알 수 있음).
public enum PhotoAvailability: Sendable, Equatable {
    case available
    /// 보관함에서 삭제됐거나 파일 북마크를 해석할 수 없음.
    case missing
    /// 보관함 사진이지만 편집할 수 없음 (공유 앨범 등).
    case notEditable
    /// 아직 확인 전.
    case unknown
}

/// 사진 상태 (기획서 §4.5).
public enum PhotoStatus: Sendable, Equatable {
    case unassigned
    /// 할당됨(대기): 일괄 적용 대상.
    case pending
    /// 적용됨: 마지막 적용 값과 할당이 같음.
    case applied
    case failed(String)
    case notEditable
    case unsupported
    case missing

    /// 할당·적용할 수 없는 상태.
    public var isBlocked: Bool {
        switch self {
        case .notEditable, .unsupported, .missing: true
        default: false
        }
    }
}

extension PhotoRef {
    public func status(availability: PhotoAvailability) -> PhotoStatus {
        if availability == .missing { return .missing }
        if !isWritableFormat { return .unsupported }
        if availability == .notEditable { return .notEditable }
        if let lastError, assignment != nil, assignment != appliedAssignment { return .failed(lastError) }
        guard let assignment else { return .unassigned }
        return assignment == appliedAssignment ? .applied : .pending
    }
}
