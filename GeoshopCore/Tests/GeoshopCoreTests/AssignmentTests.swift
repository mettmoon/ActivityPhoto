import Foundation
import SwiftData
import Testing
@testable import GeoshopCore

@MainActor
@Suite("할당")
struct AssignmentTests {
    let container: ModelContainer
    let store: ProjectStore
    let project: Project
    let photos: [PhotoRef]

    init() throws {
        container = try GeoshopSchema.makeContainer(inMemory: true)
        store = ProjectStore(context: container.mainContext, trackDirectory: FileManager.default.temporaryDirectory)
        project = Project(name: "p", sourceKind: .photoLibrary, timeZoneID: "Asia/Seoul")
        container.mainContext.insert(project)
        photos = (0..<3).map { PhotoRef(assetIdentifier: "id\($0)", fileName: "IMG_\($0).HEIC", isWritableFormat: true) }
        project.photos.append(contentsOf: photos)
    }

    let here = Assignment(date: Fixture.date("2026-05-01T01:05:00Z"), latitude: 37.6, longitude: 126.9, altitude: 300)
    let there = Assignment(date: Fixture.date("2026-05-01T02:00:00Z"), latitude: 37.7, longitude: 127.0, altitude: nil)

    @Test("여러 장에 같은 지점을 할당하고, 이전 상태로 되돌리고, 다시 실행한다")
    func assignUndoRedo() throws {
        try store.setAssignment(there, for: [photos[2]])

        let undo = try store.setAssignment(here, for: photos)
        #expect(photos.allSatisfy { $0.assignment == here })
        #expect(undo.entries.map(\.assignment) == [nil, nil, there])

        let redo = try store.restore(undo)
        #expect(photos.map(\.assignment) == [nil, nil, there])

        try store.restore(redo)
        #expect(photos.allSatisfy { $0.assignment == here })
    }

    @Test("이미 같은 값인 사진은 스냅샷에 넣지 않는다")
    func unchangedPhotosAreSkipped() throws {
        try store.setAssignment(here, for: [photos[0]])
        let snapshot = try store.setAssignment(here, for: photos)
        #expect(snapshot.entries.map(\.photo.id) == [photos[1].id, photos[2].id])
        #expect(try store.setAssignment(here, for: photos).isEmpty)
    }

    @Test("할당 해제, 적용된 사진을 다시 할당하면 대기, 실패 사유는 지우고 되돌리면 복원")
    func unassignAndStatus() throws {
        let photo = photos[0]
        try store.setAssignment(here, for: [photo])
        photo.appliedAssignment = here
        #expect(photo.status(availability: .available) == .applied)

        try store.setAssignment(there, for: [photo])
        #expect(photo.status(availability: .available) == .pending)

        photo.lastError = "실패"
        #expect(photo.status(availability: .available) == .failed("실패"))
        let undo = try store.setAssignment(nil, for: [photo])
        #expect(photo.assignment == nil)
        #expect(photo.lastError == nil)
        #expect(photo.status(availability: .available) == .unassigned)

        try store.restore(undo)
        #expect(photo.assignment == there)
        #expect(photo.lastError == "실패")
    }

    @Test("트랙 위 지점으로 할당 값 만들기")
    func assignmentFromLocation() {
        let location = TrackLocation(date: here.date, latitude: 37.6, longitude: 126.9, elevation: 300, distance: 1200, segmentIndex: 0)
        #expect(Assignment(location) == here)
    }
}
