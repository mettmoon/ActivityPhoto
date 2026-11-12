import GeoshopCore
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    @Entry var projectStore: ProjectStore?
}

extension UTType {
    /// GPX. 시스템에 선언된 타입이 없으면 확장자 기반 동적 타입.
    static let gpx = UTType("com.topografix.gpx") ?? UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
}

enum TrackPalette {
    private static let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .red, .indigo, .brown]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

extension PhotoSourceKind {
    var title: String {
        switch self {
        case .photoLibrary: "사진 앱 보관함"
        case .files: "파일"
        }
    }

    var detail: String {
        switch self {
        case .photoLibrary: "보관함의 촬영일·위치 정보를 바꿉니다. 원본 파일은 그대로 둡니다."
        case .files: "JPEG·HEIC 등 파일의 EXIF를 직접 고쳐 원본에 덮어씁니다."
        }
    }

    var systemImage: String {
        switch self {
        case .photoLibrary: "photo.on.rectangle"
        case .files: "folder"
        }
    }
}

extension TrackImportError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noFiles:
            "GPX 파일을 하나 이상 선택하세요."
        case .unreadable(let fileName):
            "‘\(fileName)’ 파일을 읽을 수 없습니다."
        case .invalidGPX(let fileName, let error):
            "‘\(fileName)’: \(error.message)"
        case .lastTrack:
            "프로젝트에는 GPX가 최소 1개 있어야 합니다."
        }
    }
}

extension GPXParseError {
    var message: String {
        switch self {
        case .invalidXML(let line, _): "XML 형식 오류 (\(line)번째 줄)"
        case .notGPX: "GPX 파일이 아닙니다."
        case .noTrackPoints: "트랙 포인트가 없습니다. 경로(rte)나 웨이포인트만 있는 GPX는 쓸 수 없습니다."
        case .noTimestamps: "시각 정보가 없는 GPX입니다. 촬영일시를 정하려면 트랙 포인트에 시각이 있어야 합니다."
        }
    }
}

extension TimeZone {
    /// "Asia/Seoul (GMT+09:00)"
    func label(at date: Date = .now) -> String {
        "\(identifier) (GMT\(offsetString(at: date)))"
    }
}

extension Date {
    func formatted(in timeZone: TimeZone) -> String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: timeZone))
    }
}

func formatDistance(_ meters: Double) -> String {
    Measurement(value: meters / 1000, unit: UnitLength.kilometers)
        .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
}
