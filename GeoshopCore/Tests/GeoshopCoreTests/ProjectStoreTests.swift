import Foundation
import SwiftData
import Testing
@testable import GeoshopCore

@MainActor
@Suite("프로젝트 저장소")
final class ProjectStoreTests {
    let root: URL
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let paris = TimeZone(identifier: "Europe/Paris")!

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "GeoshopCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var storeURL: URL { root.appending(path: "Geoshop.store") }
    var trackDirectory: URL { root.appending(path: "Tracks", directoryHint: .isDirectory) }

    func makeStore(resolver: TimeZone? = nil, container: ModelContainer) -> ProjectStore {
        ProjectStore(
            context: container.mainContext,
            trackDirectory: trackDirectory,
            timeZoneResolver: FixedTimeZoneResolver(resolver ?? seoul),
            fallbackTimeZone: paris
        )
    }

    /// 사용자가 고른 위치에 있는 GPX 파일을 흉내 낸다.
    func writeGPX(_ fileName: String, name: String? = nil, start: String = "2026-05-01T01:00:00Z", timed: Bool = true) throws -> URL {
        let url = root.appending(path: "picked").appending(path: fileName)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let startDate = Fixture.date(start)
        let iso = ISO8601DateFormatter()
        let data = Fixture.gpx(name: name, tracks: [[[
            Fixture.pt(37.60, 126.90, ele: 100, time: timed ? iso.string(from: startDate) : nil),
            Fixture.pt(37.61, 126.90, ele: 150, time: timed ? iso.string(from: startDate.addingTimeInterval(600)) : nil),
        ]]])
        try data.write(to: url)
        return url
    }

    func storedFiles() throws -> [String] {
        guard FileManager.default.fileExists(atPath: trackDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: trackDirectory.path)
    }

    // MARK: -

    @Test("앱 재실행 후에도 프로젝트와 GPX가 복원된다 (M2 완료 기준)")
    func persistsAcrossLaunches() async throws {
        var projectID: UUID?
        do {
            let container = try GeoshopSchema.makeContainer(url: storeURL)
            let store = makeStore(container: container)
            let project = try await store.createProject(
                name: "  북한산 종주  ",
                sourceKind: .files,
                gpxURLs: [try writeGPX("day1.gpx", name: "Day 1"), try writeGPX("day2.gpx", start: "2026-05-02T01:00:00Z")]
            )
            projectID = project.id
        }

        // 원본 GPX를 지워도 프로젝트는 영향받지 않아야 한다 (복사 보관).
        try FileManager.default.removeItem(at: root.appending(path: "picked"))

        let container = try GeoshopSchema.makeContainer(url: storeURL)
        let store = makeStore(container: container)
        let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
        let project = try #require(projects.first)

        #expect(projects.count == 1)
        #expect(project.id == projectID)
        #expect(project.name == "북한산 종주")
        #expect(project.sourceKind == .files)
        #expect(project.timeZoneID == "Asia/Seoul")
        #expect(project.timeZoneIsAuto)
        #expect(!project.timeZoneNeedsReview)
        #expect(!project.overwriteConsentGiven)

        let tracks = project.sortedTracks
        #expect(tracks.map(\.displayName) == ["Day 1", "day2"])
        #expect(tracks.map(\.originalFileName) == ["day1.gpx", "day2.gpx"])
        #expect(Set(tracks.map(\.colorIndex)) == [0, 1])
        #expect(tracks.allSatisfy { $0.pointCount == 2 && $0.distance > 1000 })
        #expect(project.startTime == Fixture.date("2026-05-01T01:00:00Z"))

        let timeline = try store.timeline(for: project)
        #expect(timeline.segments.count == 2)
        #expect(timeline.location(at: Fixture.date("2026-05-02T01:05:00Z"))?.elevation == 125)
    }

    @Test("이름을 비우면 첫 GPX의 이름, 없으면 파일 이름")
    func defaultName() async throws {
        let container = try GeoshopSchema.makeContainer(inMemory: true)
        let store = makeStore(container: container)
        let named = try await store.createProject(name: nil, sourceKind: .photoLibrary, gpxURLs: [try writeGPX("a.gpx", name: "Morning Hike")])
        let unnamed = try await store.createProject(name: " ", sourceKind: .photoLibrary, gpxURLs: [try writeGPX("Afternoon Ride.gpx")])
        #expect(named.name == "Morning Hike")
        #expect(unnamed.name == "Afternoon Ride")
    }

    @Test("시간대 판별 실패 시 대체 시간대 + 확인 필요 표시")
    func timeZoneFallback() async throws {
        let container = try GeoshopSchema.makeContainer(inMemory: true)
        let store = ProjectStore(
            context: container.mainContext,
            trackDirectory: trackDirectory,
            timeZoneResolver: FixedTimeZoneResolver(nil),
            fallbackTimeZone: paris
        )
        let project = try await store.createProject(name: "x", sourceKind: .files, gpxURLs: [try writeGPX("a.gpx")])
        #expect(project.timeZoneID == "Europe/Paris")
        #expect(project.timeZoneNeedsReview)
    }

    @Test("GPX 중 하나라도 잘못되면 프로젝트도 파일도 남기지 않는다")
    func createIsAllOrNothing() async throws {
        let container = try GeoshopSchema.makeContainer(inMemory: true)
        let store = makeStore(container: container)
        let good = try writeGPX("good.gpx")
        let bad = try writeGPX("bad.gpx", timed: false)

        await #expect(throws: TrackImportError.invalidGPX(fileName: "bad.gpx", .noTimestamps)) {
            _ = try await store.createProject(name: "x", sourceKind: .files, gpxURLs: [good, bad])
        }
        await #expect(throws: TrackImportError.noFiles) {
            _ = try await store.createProject(name: "x", sourceKind: .files, gpxURLs: [])
        }
        let missing = root.appending(path: "nope.gpx")
        await #expect(throws: TrackImportError.unreadable(fileName: "nope.gpx")) {
            _ = try await store.createProject(name: "x", sourceKind: .files, gpxURLs: [missing])
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try storedFiles().isEmpty)
    }

    @Test("GPX 추가: 빈 색 인덱스를 쓰고, 시간대 오프셋이 다르면 경고")
    func addTracksWarnsOnDifferentTimeZone() async throws {
        let container = try GeoshopSchema.makeContainer(inMemory: true)
        let project = try await makeStore(container: container)
            .createProject(name: "x", sourceKind: .files, gpxURLs: [try writeGPX("a.gpx"), try writeGPX("b.gpx")])

        // 색 0을 쓰던 트랙을 지우면 다음 추가는 0을 다시 쓴다.
        let store = makeStore(container: container)
        try store.removeTrack(project.sortedTracks.first { $0.colorIndex == 0 }!, from: project)

        // 같은 오프셋(도쿄 = 서울 +09:00)은 경고 없음
        let sameOffset = try await makeStore(resolver: tokyo, container: container)
            .addTracks([try writeGPX("c.gpx")], to: project)
        #expect(sameOffset.isEmpty)
        #expect(Set(project.tracks.map(\.colorIndex)) == [0, 1])

        let different = try await makeStore(resolver: paris, container: container)
            .addTracks([try writeGPX("d.gpx", name: "Paris")], to: project)
        #expect(different == [.differentTimeZone(trackName: "Paris", trackTimeZone: paris)])
        #expect(project.tracks.count == 3)
        #expect(project.timeZoneID == "Asia/Seoul")
    }

    @Test("마지막 GPX는 지울 수 없고, 지운 GPX의 복사본은 삭제된다")
    func removeTrack() async throws {
        let container = try GeoshopSchema.makeContainer(inMemory: true)
        let store = makeStore(container: container)
        let project = try await store.createProject(name: "x", sourceKind: .files, gpxURLs: [try writeGPX("a.gpx"), try writeGPX("b.gpx")])
        #expect(try storedFiles().count == 2)

        try store.removeTrack(project.sortedTracks[0], from: project)
        #expect(project.tracks.count == 1)
        #expect(try storedFiles().count == 1)

        #expect(throws: TrackImportError.lastTrack) {
            try store.removeTrack(project.sortedTracks[0], from: project)
        }
        #expect(try storedFiles().count == 1)
    }

    @Test("프로젝트 삭제 시 GPX 복사본도 삭제")
    func deleteProject() async throws {
        let container = try GeoshopSchema.makeContainer(inMemory: true)
        let store = makeStore(container: container)
        let keep = try await store.createProject(name: "keep", sourceKind: .files, gpxURLs: [try writeGPX("a.gpx")])
        let drop = try await store.createProject(name: "drop", sourceKind: .files, gpxURLs: [try writeGPX("b.gpx"), try writeGPX("c.gpx")])
        #expect(try storedFiles().count == 3)

        try store.deleteProject(drop)
        #expect(try container.mainContext.fetch(FetchDescriptor<Project>()).map(\.name) == ["keep"])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TrackFile>()) == 1)
        #expect(try storedFiles() == [keep.tracks[0].storedFileName])
    }

    @Test("시간대 직접 지정과 자동으로 되돌리기")
    func manualAndAutomaticTimeZone() async throws {
        let container = try GeoshopSchema.makeContainer(inMemory: true)
        let store = makeStore(container: container)
        let project = try await store.createProject(name: "x", sourceKind: .files, gpxURLs: [try writeGPX("a.gpx")])

        try store.setTimeZone(paris, for: project)
        #expect(project.timeZoneID == "Europe/Paris")
        #expect(!project.timeZoneIsAuto)

        try await store.resetTimeZoneToAutomatic(for: project)
        #expect(project.timeZoneID == "Asia/Seoul")
        #expect(project.timeZoneIsAuto)

        // 자동 판별 실패: 값은 유지, 확인 필요 표시
        try await ProjectStore(context: container.mainContext, trackDirectory: trackDirectory, timeZoneResolver: FixedTimeZoneResolver(nil))
            .resetTimeZoneToAutomatic(for: project)
        #expect(project.timeZoneID == "Asia/Seoul")
        #expect(project.timeZoneNeedsReview)
    }

    @Test("UTC 오프셋 문자열")
    func offsetString() {
        let date = Fixture.date("2026-01-15T00:00:00Z")
        #expect(seoul.offsetString(at: date) == "+09:00")
        #expect(TimeZone(identifier: "America/St_Johns")!.offsetString(at: date) == "-03:30")
        #expect(TimeZone.gmt.offsetString(at: date) == "+00:00")
    }
}
