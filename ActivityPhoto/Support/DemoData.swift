#if DEBUG
import Foundation
import GeoshopCore

/// 개발용 데모 모드. `-GeoshopDemo` 인자로 실행하면 메모리 저장소에 가짜 GPX 2개로 프로젝트를 만든다.
/// 실제 저장소는 건드리지 않는다. 화면 확인·스크린샷용.
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-GeoshopDemo")
    }

    /// 데모에서 고도표 거리 기준으로 미리 고정할 지점 (0...1).
    static let pinnedFraction = 0.4

    @MainActor
    static func seed(_ store: ProjectStore) async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "GeoshopDemo", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let day1 = directory.appending(path: "북한산 Day 1.gpx")
        let day2 = directory.appending(path: "북한산 Day 2.gpx")
        try? gpx(name: "북한산 Day 1", start: "2026-05-01T00:00:00Z", center: (37.658, 126.978), radius: 0.012, peak: 836).write(to: day1, atomically: true, encoding: .utf8)
        try? gpx(name: "북한산 Day 2", start: "2026-05-02T00:30:00Z", center: (37.700, 127.010), radius: 0.008, peak: 740).write(to: day2, atomically: true, encoding: .utf8)
        _ = try? await store.createProject(name: "데모: 북한산 1박 2일", sourceKind: .files, gpxURLs: [day1, day2])
    }

    /// 원을 한 바퀴 도는 트랙. 고도는 출발점에서 반대편 봉우리까지 올랐다 내려온다.
    private static func gpx(name: String, start: String, center: (Double, Double), radius: Double, peak: Double) -> String {
        let formatter = ISO8601DateFormatter()
        let t0 = formatter.date(from: start)!
        var points = ""
        let count = 600
        for i in 0...count {
            let theta = Double(i) / Double(count) * 2 * .pi
            let lat = center.0 + radius * sin(theta)
            let lon = center.1 + radius * 1.25 * cos(theta)
            let ele = 120 + (peak - 120) * (1 - cos(theta)) / 2 + 15 * sin(theta * 9)
            let time = formatter.string(from: t0.addingTimeInterval(Double(i) * 30))
            points += "<trkpt lat=\"\(lat)\" lon=\"\(lon)\"><ele>\(ele)</ele><time>\(time)</time></trkpt>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GeoshopDemo" xmlns="http://www.topografix.com/GPX/1/1">
        <metadata><name>\(name)</name></metadata>
        <trk><name>\(name)</name><trkseg>
        \(points)</trkseg></trk>
        </gpx>
        """
    }
}
#endif
