import Foundation
@testable import GeoshopCore

enum Fixture {
    /// `<trkpt>` 목록으로 최소 GPX 1.1 문서를 만든다.
    static func gpx(name: String? = nil, tracks: [[[String]]]) -> Data {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
        """
        if let name { xml += "<metadata><name>\(name)</name></metadata>" }
        for segments in tracks {
            xml += "<trk>"
            for points in segments {
                xml += "<trkseg>" + points.joined() + "</trkseg>"
            }
            xml += "</trk>"
        }
        xml += "</gpx>"
        return Data(xml.utf8)
    }

    static func pt(_ lat: Double, _ lon: Double, ele: Double? = nil, time: String?) -> String {
        var s = "<trkpt lat=\"\(lat)\" lon=\"\(lon)\">"
        if let ele { s += "<ele>\(ele)</ele>" }
        if let time { s += "<time>\(time)</time>" }
        return s + "</trkpt>"
    }

    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: iso) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    static func point(_ lat: Double, _ lon: Double, ele: Double? = nil, _ iso: String) -> TrackPoint {
        TrackPoint(latitude: lat, longitude: lon, elevation: ele, time: date(iso))
    }

    static func document(_ segments: [[TrackPoint]], name: String? = nil) -> GPXDocument {
        GPXDocument(tracks: [GPXTrack(name: name, segments: segments.map(TrackSegment.init(points:)))])
    }
}
