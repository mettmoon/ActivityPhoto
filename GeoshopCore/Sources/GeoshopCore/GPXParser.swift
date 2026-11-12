import Foundation

public enum GPXParseError: Error, Equatable, Sendable {
    /// XML 문법 오류.
    case invalidXML(line: Int, reason: String)
    /// 루트 요소가 `<gpx>`가 아님.
    case notGPX
    /// `<trk>/<trkseg>/<trkpt>`가 하나도 없음 (웨이포인트·경로만 있는 파일 포함).
    case noTrackPoints
    /// 트랙 포인트는 있지만 시각(`<time>`)이 있는 것이 하나도 없음.
    case noTimestamps
}

/// GPX 1.0 / 1.1 파서.
///
/// 규칙 (기획서 §4.1)
/// - `<trk>/<trkseg>/<trkpt>`만 읽는다. `<wpt>`, `<rte>`, `<extensions>` 내부는 무시.
/// - 시각이 없거나 좌표가 잘못된 포인트는 버린다.
/// - 같은 세그먼트에서 앞 포인트보다 시각이 이른 포인트는 버린다 (시각 오름차순 보장).
/// - 시각 있는 포인트가 하나도 없으면 `noTimestamps`로 거부한다.
public enum GPXParser {
    public static func parse(contentsOf url: URL) throws -> GPXDocument {
        try parse(data: Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> GPXDocument {
        let parser = XMLParser(data: data)
        let delegate = ParsingDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false

        let ok = parser.parse()
        if delegate.rootIsNotGPX {
            throw GPXParseError.notGPX
        }
        if !ok {
            let reason = parser.parserError?.localizedDescription ?? "unknown"
            throw GPXParseError.invalidXML(line: parser.lineNumber, reason: reason)
        }
        if !delegate.sawRoot {
            throw GPXParseError.notGPX
        }
        if delegate.trackPointCount == 0 {
            throw GPXParseError.noTrackPoints
        }
        if delegate.timedTrackPointCount == 0 {
            throw GPXParseError.noTimestamps
        }
        if delegate.tracks.isEmpty {
            // 시각은 있었지만 좌표가 모두 잘못된 경우.
            throw GPXParseError.noTrackPoints
        }
        return GPXDocument(name: delegate.documentName, tracks: delegate.tracks)
    }
}

// MARK: - Delegate

private final class ParsingDelegate: NSObject, XMLParserDelegate {
    private(set) var sawRoot = false
    private(set) var rootIsNotGPX = false
    private(set) var documentName: String?
    private(set) var tracks: [GPXTrack] = []
    private(set) var trackPointCount = 0
    private(set) var timedTrackPointCount = 0

    private var stack: [String] = []
    private var text = ""
    private let timeParser = GPXTimeParser()

    private var trackName: String?
    private var segments: [TrackSegment] = []
    private var points: [TrackPoint] = []

    private var pointLatitude: Double?
    private var pointLongitude: Double?
    private var pointElevation: Double?
    private var pointTime: Date?

    private var parent: String? { stack.count >= 2 ? stack[stack.count - 2] : nil }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let name = localName(elementName)
        stack.append(name)
        text = ""

        if stack.count == 1 {
            guard name == "gpx" else {
                rootIsNotGPX = true
                parser.abortParsing()
                return
            }
            sawRoot = true
            return
        }

        switch (name, parent) {
        case ("trk", "gpx"):
            trackName = nil
            segments = []
        case ("trkseg", "trk"):
            points = []
        case ("trkpt", "trkseg"):
            pointLatitude = attributes["lat"].flatMap(parseDouble)
            pointLongitude = attributes["lon"].flatMap(parseDouble)
            pointElevation = nil
            pointTime = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            stack.removeLast()
            text = ""
        }

        switch (name, parent) {
        case ("ele", "trkpt"):
            pointElevation = parseDouble(value)
        case ("time", "trkpt"):
            pointTime = timeParser.date(from: value)
        case ("name", "trk"):
            trackName = value.isEmpty ? nil : value
        case ("name", "gpx"), ("name", "metadata"):
            if documentName == nil, !value.isEmpty { documentName = value }
        case ("trkpt", "trkseg"):
            finishPoint()
        case ("trkseg", "trk"):
            if !points.isEmpty { segments.append(TrackSegment(points: points)) }
            points = []
        case ("trk", "gpx"):
            if !segments.isEmpty { tracks.append(GPXTrack(name: trackName, segments: segments)) }
            segments = []
        default:
            break
        }
    }

    private func finishPoint() {
        trackPointCount += 1
        guard let time = pointTime else { return }
        timedTrackPointCount += 1
        guard
            let lat = pointLatitude, (-90...90).contains(lat),
            let lon = pointLongitude, (-180...180).contains(lon)
        else { return }
        if let last = points.last, time < last.time { return }
        points.append(TrackPoint(latitude: lat, longitude: lon, elevation: pointElevation, time: time))
    }

    private func localName(_ name: String) -> String {
        guard let colon = name.lastIndex(of: ":") else { return name }
        return String(name[name.index(after: colon)...])
    }

    private func parseDouble(_ string: String) -> Double? {
        guard let value = Double(string.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        return value
    }
}

// MARK: - Time

/// ISO 8601 시각 파서. 소수 초 유무, `Z`/`+09:00` 오프셋을 모두 받고,
/// 시간대 표기가 없으면 GPX 규격대로 UTC로 본다.
struct GPXTimeParser {
    private let plain: ISO8601DateFormatter
    private let fractional: ISO8601DateFormatter

    init() {
        plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func date(from string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        if let date = parse(string) { return date }
        return parse(string + "Z")
    }

    private func parse(_ string: String) -> Date? {
        plain.date(from: string) ?? fractional.date(from: string)
    }
}
