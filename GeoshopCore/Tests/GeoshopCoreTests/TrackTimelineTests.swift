import Foundation
import Testing
@testable import GeoshopCore

@Suite("트랙 타임라인")
struct TrackTimelineTests {
    /// 적도 위 경도 방향 직선: 0.01도(≈1.11 km)마다 10분, 고도 100 → 200 → 300.
    let straight = Fixture.document([[
        Fixture.point(0, 0.00, ele: 100, "2026-05-01T01:00:00Z"),
        Fixture.point(0, 0.01, ele: 200, "2026-05-01T01:10:00Z"),
        Fixture.point(0, 0.02, ele: 300, "2026-05-01T01:20:00Z"),
    ]])

    // MARK: 시각 → 지점

    @Test("두 포인트 사이 시각은 좌표·고도·거리를 선형 보간한다")
    func interpolatesByTime() throws {
        let timeline = TrackTimeline(documents: [straight])
        let loc = try #require(timeline.location(at: Fixture.date("2026-05-01T01:05:00Z")))

        #expect(loc.latitude == 0)
        #expect(abs(loc.longitude - 0.005) < 1e-12)
        #expect(loc.elevation == 150)
        #expect(abs(loc.distance - timeline.totalDistance / 4) < 1e-6)
        #expect(loc.segmentIndex == 0)
    }

    @Test("포인트와 정확히 같은 시각, 시작·끝 시각")
    func exactTimes() throws {
        let timeline = TrackTimeline(documents: [straight])
        #expect(timeline.location(at: Fixture.date("2026-05-01T01:00:00Z"))?.elevation == 100)
        #expect(timeline.location(at: Fixture.date("2026-05-01T01:10:00Z"))?.elevation == 200)
        let end = try #require(timeline.location(at: Fixture.date("2026-05-01T01:20:00Z")))
        #expect(end.elevation == 300)
        #expect(end.distance == timeline.totalDistance)
    }

    @Test("트랙 범위 밖 시각은 nil")
    func outOfRangeTime() {
        let timeline = TrackTimeline(documents: [straight])
        #expect(timeline.location(at: Fixture.date("2026-05-01T00:59:59Z")) == nil)
        #expect(timeline.location(at: Fixture.date("2026-05-01T01:20:01Z")) == nil)
    }

    @Test("한쪽만 고도가 있으면 있는 값을, 둘 다 없으면 nil")
    func partialElevation() {
        let doc = Fixture.document([[
            Fixture.point(0, 0, ele: 50, "2026-05-01T01:00:00Z"),
            Fixture.point(0, 0.01, "2026-05-01T01:10:00Z"),
            Fixture.point(0, 0.02, "2026-05-01T01:20:00Z"),
        ]])
        let timeline = TrackTimeline(documents: [doc])
        #expect(timeline.location(at: Fixture.date("2026-05-01T01:05:00Z"))?.elevation == 50)
        #expect(timeline.location(at: Fixture.date("2026-05-01T01:15:00Z"))?.elevation == nil)
    }

    // MARK: 누적 거리 → 지점

    @Test("누적 거리로 찾은 지점은 같은 시각으로 찾은 지점과 같다")
    func distanceAndTimeAgree() throws {
        let timeline = TrackTimeline(documents: [straight])
        let byTime = try #require(timeline.location(at: Fixture.date("2026-05-01T01:13:00Z")))
        let byDistance = try #require(timeline.location(atDistance: byTime.distance))

        #expect(abs(byDistance.date.timeIntervalSince(byTime.date)) < 1e-3)
        #expect(abs(byDistance.longitude - byTime.longitude) < 1e-12)
        #expect(byDistance.elevation.map { abs($0 - byTime.elevation!) < 1e-9 } == true)
    }

    @Test("거리 범위 밖은 양 끝으로 고정")
    func clampsDistance() {
        let timeline = TrackTimeline(documents: [straight])
        #expect(timeline.location(atDistance: -10)?.elevation == 100)
        #expect(timeline.location(atDistance: 1e9)?.elevation == 300)
    }

    @Test("정지 구간(같은 거리)에서는 가장 이른 시각을 고른다")
    func stationaryPicksEarliest() {
        let doc = Fixture.document([[
            Fixture.point(0, 0, "2026-05-01T01:00:00Z"),
            Fixture.point(0, 0.01, "2026-05-01T01:10:00Z"),
            Fixture.point(0, 0.01, "2026-05-01T01:30:00Z"),
            Fixture.point(0, 0.02, "2026-05-01T01:40:00Z"),
        ]])
        let timeline = TrackTimeline(documents: [doc])
        let d = timeline.segments[0].cumulativeDistances[1]
        #expect(timeline.location(atDistance: d)?.date == Fixture.date("2026-05-01T01:10:00Z"))
    }

    // MARK: 여러 GPX 병합

    @Test("여러 GPX는 시작 시각 순으로 정렬하고 누적 거리는 공백 없이 이어진다")
    func mergesDocumentsChronologically() throws {
        let day2 = Fixture.document([[
            Fixture.point(10, 0.00, "2026-05-02T01:00:00Z"),
            Fixture.point(10, 0.01, "2026-05-02T01:10:00Z"),
        ]], name: "Day 2")
        let day1 = Fixture.document([[
            Fixture.point(0, 0.00, "2026-05-01T01:00:00Z"),
            Fixture.point(0, 0.01, "2026-05-01T01:10:00Z"),
        ]], name: "Day 1")

        // 입력 순서는 Day 2, Day 1
        let timeline = TrackTimeline(documents: [day2, day1])

        #expect(timeline.segments.map(\.trackName) == ["Day 1", "Day 2"])
        #expect(timeline.segments.map(\.documentIndex) == [1, 0])
        let seg0 = timeline.segments[0], seg1 = timeline.segments[1]
        // Day 1 끝과 Day 2 시작 사이(위도 10도 차이)는 거리에 더하지 않는다.
        #expect(seg1.startDistance == seg0.endDistance)
        #expect(timeline.startTime == Fixture.date("2026-05-01T01:00:00Z"))
        #expect(timeline.endTime == Fixture.date("2026-05-02T01:10:00Z"))

        // 공백 시각은 nil, 각 세그먼트 안은 해당 세그먼트에서 찾는다.
        #expect(timeline.location(at: Fixture.date("2026-05-01T12:00:00Z")) == nil)
        let loc = try #require(timeline.location(at: Fixture.date("2026-05-02T01:05:00Z")))
        #expect(loc.segmentIndex == 1)
        #expect(loc.latitude == 10)

        // 세그먼트 경계 거리 → 앞 세그먼트의 끝
        #expect(timeline.location(atDistance: seg0.endDistance)?.date == Fixture.date("2026-05-01T01:10:00Z"))
        // 경계를 조금 넘으면 뒤 세그먼트
        #expect(timeline.location(atDistance: seg0.endDistance + 1)?.segmentIndex == 1)
    }

    @Test("한 GPX 안의 여러 세그먼트도 같은 규칙으로 이어 붙인다")
    func mergesSegmentsInOneDocument() {
        let doc = Fixture.document([
            [Fixture.point(0, 0, "2026-05-01T03:00:00Z"), Fixture.point(0, 0.01, "2026-05-01T03:10:00Z")],
            [Fixture.point(0, 0, "2026-05-01T01:00:00Z"), Fixture.point(0, 0.01, "2026-05-01T01:10:00Z")],
        ])
        let timeline = TrackTimeline(documents: [doc])
        #expect(timeline.segments.map(\.startTime) == [
            Fixture.date("2026-05-01T01:00:00Z"), Fixture.date("2026-05-01T03:00:00Z"),
        ])
        #expect(abs(timeline.totalDistance - 2 * timeline.segments[0].endDistance) < 1e-6)
    }

    @Test("빈 타임라인")
    func emptyTimeline() {
        let timeline = TrackTimeline(documents: [])
        #expect(timeline.isEmpty)
        #expect(timeline.totalDistance == 0)
        #expect(timeline.location(atDistance: 0) == nil)
        #expect(timeline.location(at: .now) == nil)
        #expect(timeline.snapCandidates(latitude: 0, longitude: 0, radius: 100).isEmpty)
    }

    // MARK: 지도 클릭 스냅 (D9)

    /// 위도 방향으로 0.01도 올라갔다가(10분) 1시간 쉬고 같은 길로 내려오는(10분) 왕복 트랙.
    let outAndBack = Fixture.document([[
        Fixture.point(0.00, 0, ele: 100, "2026-05-01T01:00:00Z"),
        Fixture.point(0.01, 0, ele: 200, "2026-05-01T01:10:00Z"),
        Fixture.point(0.01, 0, ele: 200, "2026-05-01T02:10:00Z"),
        Fixture.point(0.00, 0, ele: 100, "2026-05-01T02:20:00Z"),
    ]])

    @Test("왕복 코스의 겹치는 곳은 갈 때·올 때 두 후보")
    func outAndBackGivesTwoCandidates() throws {
        let timeline = TrackTimeline(documents: [outAndBack])
        // 중간 지점에서 동쪽으로 약 5 m 떨어진 곳 클릭
        let candidates = timeline.snapCandidates(latitude: 0.005, longitude: 0.000045, radius: 30)

        #expect(candidates.count == 2)
        let dates = candidates.map(\.location.date).sorted()
        #expect(abs(dates[0].timeIntervalSince(Fixture.date("2026-05-01T01:05:00Z"))) < 1)
        #expect(abs(dates[1].timeIntervalSince(Fixture.date("2026-05-01T02:15:00Z"))) < 1)
        for candidate in candidates {
            #expect(abs(candidate.offset - 5) < 0.1)
            #expect(candidate.location.longitude == 0)
            #expect(abs(candidate.location.latitude - 0.005) < 1e-9)
            #expect(candidate.location.elevation.map { abs($0 - 150) < 1e-6 } == true)
        }
    }

    @Test("반경 밖이면 후보 없음")
    func nothingOutsideRadius() {
        let timeline = TrackTimeline(documents: [outAndBack])
        // 동쪽으로 약 111 m
        #expect(timeline.snapCandidates(latitude: 0.005, longitude: 0.001, radius: 30).isEmpty)
    }

    @Test("한 번만 지나는 곳은 후보 하나 (인접 조각의 중복도 하나로)")
    func singlePassGivesOneCandidate() throws {
        let timeline = TrackTimeline(documents: [straight])
        // 꼭짓점(0, 0.01) 바로 옆: 두 조각 모두 반경 안
        let candidates = timeline.snapCandidates(latitude: 0.00005, longitude: 0.01, radius: 30)
        let only = try #require(candidates.first)
        #expect(candidates.count == 1)
        #expect(only.location.date == Fixture.date("2026-05-01T01:10:00Z"))
    }

    @Test("5분 이내로 다시 지나간 후보는 하나로 묶고 가장 가까운 것을 쓴다")
    func mergesCandidatesWithinSeparation() {
        // 북쪽으로 갔다가 2분 만에 되돌아옴. 되돌아오는 길이 클릭 지점에 더 가깝다.
        let doc = Fixture.document([[
            Fixture.point(0.0000, 0.00000, "2026-05-01T01:00:00Z"),
            Fixture.point(0.0010, 0.00000, "2026-05-01T01:01:00Z"),
            Fixture.point(0.0000, 0.00010, "2026-05-01T01:02:00Z"),
        ]])
        let timeline = TrackTimeline(documents: [doc])
        let candidates = timeline.snapCandidates(latitude: 0.0005, longitude: 0.00009, radius: 30)

        #expect(candidates.count == 1)
        #expect(candidates.first.map { $0.location.date > Fixture.date("2026-05-01T01:01:00Z") } == true)

        // 기준을 30초로 줄이면 두 후보로 나뉜다.
        let strict = timeline.snapCandidates(latitude: 0.0005, longitude: 0.00009, radius: 30, minimumTimeSeparation: 30)
        #expect(strict.count == 2)
        #expect(strict[0].offset <= strict[1].offset)
    }

    @Test("포인트 하나짜리 세그먼트도 스냅 대상")
    func singlePointSegment() {
        let doc = Fixture.document([[Fixture.point(1, 1, ele: 7, "2026-05-01T01:00:00Z")]])
        let timeline = TrackTimeline(documents: [doc])
        let candidates = timeline.snapCandidates(latitude: 1, longitude: 1.0001, radius: 30)
        #expect(candidates.count == 1)
        #expect(candidates.first?.location.elevation == 7)
    }
}
