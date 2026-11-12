#if DEBUG
import AppKit
import GeoshopCore
import ImageIO

/// 개발용 데모 모드. `-GeoshopDemo` 인자로 실행하면 메모리 저장소에 가짜 GPX 2개로 프로젝트를 만든다.
/// 실제 저장소는 건드리지 않는다. 화면 확인·스크린샷용.
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-GeoshopDemo")
    }

    @MainActor
    static func seed(_ store: ProjectStore) async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "GeoshopDemo", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let day1 = directory.appending(path: "북한산 Day 1.gpx")
        let day2 = directory.appending(path: "북한산 Day 2.gpx")
        try? gpx(name: "북한산 Day 1", start: "2026-05-01T00:00:00Z", center: (37.658, 126.978), radius: 0.012, peak: 836).write(to: day1, atomically: true, encoding: .utf8)
        try? gpx(name: "북한산 Day 2", start: "2026-05-02T00:30:00Z", center: (37.700, 127.010), radius: 0.008, peak: 740, outAndBack: true).write(to: day2, atomically: true, encoding: .utf8)
        guard let project = try? await store.createProject(name: "데모: 북한산 1박 2일", sourceKind: .files, gpxURLs: [day1, day2])
        else { return }
        seedPhotos(store: store, project: project, directory: directory.appending(path: "Photos", directoryHint: .isDirectory))
    }

    /// 상태별 사진: 미할당(기존 정보 있음/없음), 대기, 적용됨, 미지원 형식(GIF), 찾을 수 없음(추가 후 삭제).
    @MainActor
    private static func seedPhotos(store: ProjectStore, project: Project, directory: URL) {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hues: [CGFloat] = [0.08, 0.3, 0.55, 0.62, 0.75, 0.9, 0.45]
        for (i, hue) in hues.enumerated() {
            let date = i < 4 ? String(format: "2026:05:01 %02d:%02d:00", 9 + i, 10 * i) : nil
            writeImage(directory.appending(path: String(format: "IMG_%04d.jpg", 4821 + i)), hue: hue, type: "public.jpeg",
                       dateTimeOriginal: date, offset: i % 2 == 0 ? "+09:00" : nil, gps: i == 0 ? (37.66, 126.98) : nil)
        }
        writeImage(directory.appending(path: "animation.gif"), hue: 0.15, type: "com.compuserve.gif", dateTimeOriginal: nil, offset: nil, gps: nil)
        let doomed = directory.appending(path: "IMG_DELETED.jpg")
        writeImage(doomed, hue: 0.0, type: "public.jpeg", dateTimeOriginal: nil, offset: nil, gps: nil)

        _ = try? store.addPhotos(fileURLs: [directory], to: project)
        try? FileManager.default.removeItem(at: doomed)

        let photos = project.photos.sorted { $0.fileName < $1.fileName }
        if let timeline = try? store.timeline(for: project) {
            if let pending = photos.first(where: { $0.fileName == "IMG_4822.jpg" }),
               let location = timeline.location(atDistance: timeline.totalDistance * 0.2) {
                pending.assignment = Assignment(location)
            }
            if let applied = photos.first(where: { $0.fileName == "IMG_4823.jpg" }),
               let location = timeline.location(atDistance: timeline.totalDistance * 0.3) {
                applied.assignment = Assignment(location)
                applied.appliedAssignment = applied.assignment
            }
        }
        try? store.save()
    }

    private static func writeImage(_ url: URL, hue: CGFloat, type: String, dateTimeOriginal: String?, offset: String?, gps: (Double, Double)?) {
        let size = 480
        guard let context = CGContext(data: nil, width: size, height: size * 3 / 4, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        let sky = NSColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1).cgColor
        let ground = NSColor(hue: hue, saturation: 0.7, brightness: 0.55, alpha: 1).cgColor
        context.setFillColor(sky)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(ground)
        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: 0, y: 120))
        context.addLine(to: CGPoint(x: 170, y: 290))
        context.addLine(to: CGPoint(x: 280, y: 190))
        context.addLine(to: CGPoint(x: 360, y: 250))
        context.addLine(to: CGPoint(x: size, y: 110))
        context.addLine(to: CGPoint(x: size, y: 0))
        context.fillPath()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)
        else { return }
        var properties: [CFString: Any] = [:]
        var exif: [CFString: Any] = [:]
        if let dateTimeOriginal { exif[kCGImagePropertyExifDateTimeOriginal] = dateTimeOriginal }
        if let offset { exif[kCGImagePropertyExifOffsetTimeOriginal] = offset }
        if !exif.isEmpty { properties[kCGImagePropertyExifDictionary] = exif }
        if let gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: gps.0, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: gps.1, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    /// 원을 한 바퀴 도는 트랙(고도는 반대편 봉우리까지 올랐다 내려옴), 또는 같은 길로 왕복하는 트랙.
    private static func gpx(name: String, start: String, center: (Double, Double), radius: Double, peak: Double, outAndBack: Bool = false) -> String {
        let formatter = ISO8601DateFormatter()
        let t0 = formatter.date(from: start)!
        var points = ""
        let count = 600
        for i in 0...count {
            let theta = Double(i) / Double(count) * 2 * .pi
            let lat: Double, lon: Double, ele: Double
            if outAndBack {
                // 0 → 1 → 0: 정상까지 갔다가 같은 길로 내려온다.
                let s = 1 - abs(1 - 2 * Double(i) / Double(count))
                lat = center.0 + radius * (2 * s - 1)
                lon = center.1 + radius * 0.4 * sin(s * 3 * .pi)
                ele = 120 + (peak - 120) * s + 10 * sin(s * 20)
            } else {
                lat = center.0 + radius * sin(theta)
                lon = center.1 + radius * 1.25 * cos(theta)
                ele = 120 + (peak - 120) * (1 - cos(theta)) / 2 + 15 * sin(theta * 9)
            }
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
