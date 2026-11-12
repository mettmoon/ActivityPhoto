import Foundation
import Testing
@testable import GeoshopCore

@Suite("지도·고도표 표시 데이터")
struct TrackDisplayTests {
    /// 적도를 따라 동쪽으로 1초에 약 1.1 m씩, 고도는 사인파. 300번째 포인트에 봉우리 9999 m.
    static func longTrack(count: Int, start: String = "2026-05-01T01:00:00Z", peakAt: Int? = 300) -> [TrackPoint] {
        let t0 = Fixture.date(start)
        return (0..<count).map { i in
            let elevation = i == peakAt ? 9_999 : 100 + 50 * sin(Double(i) / 40)
            return TrackPoint(latitude: 0, longitude: Double(i) * 0.00001, elevation: elevation, time: t0.addingTimeInterval(Double(i)))
        }
    }

    @Test("고도표 샘플은 예산 이하로 줄이되 처음·끝·봉우리를 남긴다")
    func profileDownsamples() throws {
        let points = Self.longTrack(count: 10_000)
        let timeline = TrackTimeline(documents: [Fixture.document([points])])
        let series = try #require(timeline.elevationProfile(maxSamples: 500).first)

        #expect(series.samples.count <= 500)
        #expect(series.samples.count > 400)
        #expect(series.samples.first?.date == points.first?.time)
        #expect(series.samples.last?.date == points.last?.time)
        #expect(series.samples.contains { $0.elevation == 9_999 })
        // 거리·시각 순서 유지
        #expect(zip(series.samples, series.samples.dropFirst()).allSatisfy { $0.distance <= $1.distance && $0.date <= $1.date })
    }

    @Test("포인트가 적으면 그대로, 세그먼트마다 별도 선, 고도 없는 점은 제외")
    func profileSeriesPerSegment() {
        let doc = Fixture.document([
            [
                Fixture.point(0, 0.00, ele: 10, "2026-05-01T01:00:00Z"),
                Fixture.point(0, 0.01, "2026-05-01T01:10:00Z"),
                Fixture.point(0, 0.02, ele: 30, "2026-05-01T01:20:00Z"),
            ],
            [
                Fixture.point(1, 0, "2026-05-01T02:00:00Z"),
                Fixture.point(1, 1, "2026-05-01T02:10:00Z"),
            ],
            [
                Fixture.point(2, 0, ele: 5, "2026-05-01T03:00:00Z"),
            ],
        ])
        let profile = TrackTimeline(documents: [doc]).elevationProfile()

        #expect(profile.map(\.segmentIndex) == [0, 2])
        #expect(profile[0].samples.map(\.elevation) == [10, 30])
        #expect(profile[1].samples.map(\.elevation) == [5])
    }

    @Test("예산은 세그먼트 포인트 수에 비례해 나눈다")
    func profileBudgetIsProportional() {
        let big = Self.longTrack(count: 9_000, peakAt: nil)
        let small = Self.longTrack(count: 1_000, start: "2026-05-02T01:00:00Z", peakAt: nil)
        let profile = TrackTimeline(documents: [Fixture.document([big, small])]).elevationProfile(maxSamples: 1_000)

        #expect(profile.count == 2)
        #expect((850...900).contains(profile[0].samples.count))
        #expect((80...100).contains(profile[1].samples.count))
    }

    @Test("지도 경로는 가까운 점을 건너뛰되 처음·끝은 남긴다")
    func displayPathDecimates() {
        // 약 1.1 m 간격 1000개 → 5 m 간격이면 약 1/5
        let points = Self.longTrack(count: 1_000)
        let timeline = TrackTimeline(documents: [Fixture.document([points])])
        let path = timeline.displayPath(segmentIndex: 0, minimumSpacing: 5)

        #expect((190...210).contains(path.count))
        #expect(path.first == points.first)
        #expect(path.last == points.last)
        #expect(timeline.displayPath(segmentIndex: 0, minimumSpacing: 0).count == 1_000)
    }

    @Test("고도 범위와 좌표 범위")
    func ranges() throws {
        let doc = Fixture.document([
            [Fixture.point(37.5, 127.0, ele: 120, "2026-05-01T01:00:00Z"), Fixture.point(37.7, 126.8, "2026-05-01T01:10:00Z")],
            [Fixture.point(37.6, 127.2, ele: -3, "2026-05-01T02:00:00Z")],
        ])
        let timeline = TrackTimeline(documents: [doc])
        #expect(timeline.elevationRange == -3...120)
        let bounds = try #require(timeline.bounds)
        #expect(bounds == CoordinateBounds(minLatitude: 37.5, maxLatitude: 37.7, minLongitude: 126.8, maxLongitude: 127.2))

        let noElevation = TrackTimeline(documents: [Fixture.document([[Fixture.point(0, 0, "2026-05-01T01:00:00Z")]])])
        #expect(noElevation.elevationRange == nil)
        #expect(TrackTimeline(documents: []).bounds == nil)
    }

    @Test("호버용 최근접 지점은 왕복 코스에서도 하나만, 가장 가까운 것")
    func nearestLocationPicksClosest() throws {
        let doc = Fixture.document([[
            Fixture.point(0.00, 0, "2026-05-01T01:00:00Z"),
            Fixture.point(0.01, 0, "2026-05-01T01:10:00Z"),
            Fixture.point(0.00, 0.0001, "2026-05-01T02:00:00Z"),
        ]])
        let timeline = TrackTimeline(documents: [doc])
        // 내려오는 길(동쪽으로 약 5.5 m 치우친 쪽)에 더 가까운 클릭
        let nearest = try #require(timeline.nearestLocation(latitude: 0.005, longitude: 0.00008, radius: 30))
        #expect(nearest.date > Fixture.date("2026-05-01T01:10:00Z"))
        #expect(timeline.nearestLocation(latitude: 0.005, longitude: 0.01, radius: 30) == nil)
    }
}
