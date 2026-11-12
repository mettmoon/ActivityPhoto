import Foundation
import Testing
@testable import GeoshopCore

@Suite("GPX 파싱")
struct GPXParserTests {
    @Test("GPX 1.1 트랙 포인트의 좌표·고도·시각을 읽는다")
    func parsesBasicTrack() throws {
        let data = Fixture.gpx(name: "북한산", tracks: [[[
            Fixture.pt(37.6, 126.9, ele: 100.5, time: "2026-05-01T01:00:00Z"),
            Fixture.pt(37.61, 126.91, ele: 120, time: "2026-05-01T01:10:00Z"),
        ]]])

        let doc = try GPXParser.parse(data: data)

        #expect(doc.name == "북한산")
        #expect(doc.tracks.count == 1)
        #expect(doc.pointCount == 2)
        let first = try #require(doc.tracks.first?.segments.first?.points.first)
        #expect(first.latitude == 37.6)
        #expect(first.longitude == 126.9)
        #expect(first.elevation == 100.5)
        #expect(first.time == Fixture.date("2026-05-01T01:00:00Z"))
        #expect(doc.startTime == Fixture.date("2026-05-01T01:00:00Z"))
        #expect(doc.endTime == Fixture.date("2026-05-01T01:10:00Z"))
    }

    @Test("시각 형식: 소수 초, 오프셋, 시간대 없음(UTC로 간주)")
    func parsesTimeFormats() throws {
        let data = Fixture.gpx(tracks: [[[
            Fixture.pt(0, 0, time: "2026-05-01T01:00:00.250Z"),
            Fixture.pt(0, 0, time: "2026-05-01T10:00:01+09:00"),
            Fixture.pt(0, 0, time: "2026-05-01T01:00:02"),
            Fixture.pt(0, 0, time: "2026-05-01T01:00:03.5"),
        ]]])

        let points = try GPXParser.parse(data: data).tracks[0].segments[0].points
        let base = Fixture.date("2026-05-01T01:00:00Z")
        #expect(points.map { $0.time.timeIntervalSince(base) } == [0.25, 1, 2, 3.5])
    }

    @Test("시각이 하나도 없는 GPX는 거부한다")
    func rejectsGPXWithoutTimestamps() {
        let data = Fixture.gpx(tracks: [[[
            Fixture.pt(37.6, 126.9, ele: 100, time: nil),
            Fixture.pt(37.7, 126.9, ele: 110, time: nil),
        ]]])
        #expect(throws: GPXParseError.noTimestamps) { try GPXParser.parse(data: data) }
    }

    @Test("트랙 포인트가 없는 GPX(웨이포인트만)는 거부한다")
    func rejectsGPXWithoutTrackPoints() {
        let data = Data("""
        <gpx version="1.1"><wpt lat="1" lon="2"><time>2026-05-01T01:00:00Z</time></wpt></gpx>
        """.utf8)
        #expect(throws: GPXParseError.noTrackPoints) { try GPXParser.parse(data: data) }
    }

    @Test("루트가 gpx가 아니면 거부한다")
    func rejectsNonGPX() {
        let data = Data("<kml><Document/></kml>".utf8)
        #expect(throws: GPXParseError.notGPX) { try GPXParser.parse(data: data) }
    }

    @Test("XML 문법 오류는 invalidXML")
    func rejectsMalformedXML() {
        let data = Data("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"></trkseg></gpx>".utf8)
        let error = #expect(throws: GPXParseError.self) { try GPXParser.parse(data: data) }
        guard case .invalidXML = error else {
            Issue.record("expected invalidXML, got \(String(describing: error))")
            return
        }
    }

    @Test("시각 없는 포인트, 잘못된 좌표, 시각이 거꾸로 간 포인트는 버린다")
    func dropsInvalidPoints() throws {
        let data = Fixture.gpx(tracks: [[[
            Fixture.pt(1, 1, time: "2026-05-01T01:00:00Z"),
            Fixture.pt(2, 2, time: nil),
            Fixture.pt(95, 2, time: "2026-05-01T01:00:10Z"),
            Fixture.pt(3, 3, time: "2026-05-01T01:00:20Z"),
            Fixture.pt(4, 4, time: "2026-05-01T00:59:00Z"),
            Fixture.pt(5, 5, time: "2026-05-01T01:00:20Z"),
        ]]])

        let points = try GPXParser.parse(data: data).tracks[0].segments[0].points
        #expect(points.map(\.latitude) == [1, 3, 5])
    }

    @Test("extensions 안의 time/ele, wpt, rte는 무시한다")
    func ignoresNonTrackElements() throws {
        let data = Data("""
        <gpx version="1.1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <wpt lat="9" lon="9"><time>2020-01-01T00:00:00Z</time></wpt>
          <rte><rtept lat="8" lon="8"><time>2020-01-01T00:00:00Z</time></rtept></rte>
          <trk><name>Morning Ride</name><trkseg>
            <trkpt lat="1" lon="1">
              <ele>10</ele><time>2026-05-01T01:00:00Z</time>
              <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>120</gpxtpx:hr>
                <time>1999-01-01T00:00:00Z</time><ele>999</ele>
              </gpxtpx:TrackPointExtension></extensions>
            </trkpt>
          </trkseg></trk>
        </gpx>
        """.utf8)

        let doc = try GPXParser.parse(data: data)
        #expect(doc.tracks.count == 1)
        #expect(doc.tracks[0].name == "Morning Ride")
        let point = doc.tracks[0].segments[0].points[0]
        #expect(point.elevation == 10)
        #expect(point.time == Fixture.date("2026-05-01T01:00:00Z"))
        #expect(doc.pointCount == 1)
    }

    @Test("GPX 1.0: 네임스페이스 접두어, 루트의 name, 여러 트랙·세그먼트")
    func parsesGPX10AndMultipleSegments() throws {
        let data = Data("""
        <g:gpx version="1.0" xmlns:g="http://www.topografix.com/GPX/1/0">
          <g:name>Day 1</g:name>
          <g:trk><g:trkseg>
            <g:trkpt lat="1" lon="1"><g:time>2026-05-01T01:00:00Z</g:time></g:trkpt>
          </g:trkseg><g:trkseg>
            <g:trkpt lat="2" lon="2"><g:time>2026-05-01T02:00:00Z</g:time></g:trkpt>
          </g:trkseg></g:trk>
          <g:trk><g:trkseg>
            <g:trkpt lat="3" lon="3"><g:time>2026-05-01T03:00:00Z</g:time></g:trkpt>
          </g:trkseg></g:trk>
        </g:gpx>
        """.utf8)

        let doc = try GPXParser.parse(data: data)
        #expect(doc.name == "Day 1")
        #expect(doc.tracks.map(\.segments.count) == [2, 1])
        #expect(doc.firstPoint?.latitude == 1)
    }
}
