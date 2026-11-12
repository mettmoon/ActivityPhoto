import Foundation

/// 할당 변경 전 상태. 실행 취소에 쓴다.
public struct AssignmentSnapshot {
    public struct Entry {
        public let photo: PhotoRef
        public let assignment: Assignment?
        public let lastError: String?
    }

    public let entries: [Entry]

    public var isEmpty: Bool { entries.isEmpty }
}

extension ProjectStore {
    /// 사진들에 같은 할당을 넣는다 (기획서 D5·D11). nil이면 할당 해제.
    /// 할당이 바뀐 사진은 이전 적용 실패 사유를 지운다 (새 값은 아직 적용 전이므로).
    /// - Returns: 바뀌기 전 상태. 실제로 바뀐 사진만 담긴다.
    @discardableResult
    public func setAssignment(_ assignment: Assignment?, for photos: [PhotoRef]) throws -> AssignmentSnapshot {
        var entries: [AssignmentSnapshot.Entry] = []
        for photo in photos where photo.assignment != assignment {
            entries.append(.init(photo: photo, assignment: photo.assignment, lastError: photo.lastError))
            photo.assignment = assignment
            photo.lastError = nil
        }
        if !entries.isEmpty { try save() }
        return AssignmentSnapshot(entries: entries)
    }

    /// 스냅샷 상태로 되돌린다.
    /// - Returns: 되돌리기 직전 상태 (다시 실행용).
    @discardableResult
    public func restore(_ snapshot: AssignmentSnapshot) throws -> AssignmentSnapshot {
        var current: [AssignmentSnapshot.Entry] = []
        for entry in snapshot.entries {
            current.append(.init(photo: entry.photo, assignment: entry.photo.assignment, lastError: entry.photo.lastError))
            entry.photo.assignment = entry.assignment
            entry.photo.lastError = entry.lastError
        }
        if !current.isEmpty { try save() }
        return AssignmentSnapshot(entries: current)
    }
}
