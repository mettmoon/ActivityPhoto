import Foundation
import SwiftData

/// 프로젝트의 사진 소스 (기획서 D2). 생성 후 바꿀 수 없다.
public enum PhotoSourceKind: String, Codable, CaseIterable, Sendable {
    case photoLibrary
    case files
}

@Model
public final class Project {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public private(set) var sourceKind: PhotoSourceKind
    /// IANA 시간대 ID (예: "Asia/Seoul"). 프로젝트당 하나 (D10).
    public var timeZoneID: String
    /// true면 GPX 위치로 자동 판별한 값, false면 사용자가 직접 고른 값.
    public var timeZoneIsAuto: Bool
    /// 자동 판별에 실패해 기기 시간대로 대신했음. 화면에 "시간대 확인 필요" 표시용.
    public var timeZoneNeedsReview: Bool
    /// 파일 소스 첫 적용 시 덮어쓰기 동의 (D13).
    public var overwriteConsentGiven: Bool
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TrackFile.project)
    public var tracks: [TrackFile] = []

    public init(
        id: UUID = UUID(),
        name: String,
        sourceKind: PhotoSourceKind,
        timeZoneID: String,
        timeZoneIsAuto: Bool = true,
        timeZoneNeedsReview: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sourceKind = sourceKind
        self.timeZoneID = timeZoneID
        self.timeZoneIsAuto = timeZoneIsAuto
        self.timeZoneNeedsReview = timeZoneNeedsReview
        self.overwriteConsentGiven = false
        self.createdAt = createdAt
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .gmt
    }

    /// 시작 시각 순으로 정렬한 GPX 목록.
    public var sortedTracks: [TrackFile] {
        tracks.sorted { ($0.startTime, $0.addedAt) < ($1.startTime, $1.addedAt) }
    }

    public var startTime: Date? { tracks.map(\.startTime).min() }
    public var endTime: Date? { tracks.map(\.endTime).max() }
}

/// 프로젝트에 넣은 GPX 파일 하나. 원본은 앱 컨테이너로 복사해 둔다 (§4.1).
@Model
public final class TrackFile {
    @Attribute(.unique) public var id: UUID
    public var displayName: String
    /// 원래 파일 이름 (표시·디버깅용).
    public var originalFileName: String
    /// 트랙 저장 폴더 안의 파일 이름.
    public var storedFileName: String
    /// 지도·고도표에서 트랙 색 구분용 팔레트 인덱스.
    public var colorIndex: Int
    public var startTime: Date
    public var endTime: Date
    public var pointCount: Int
    /// 트랙 길이 (미터, 세그먼트 사이 공백 제외).
    public var distance: Double
    public var addedAt: Date
    public var project: Project?

    public init(
        id: UUID = UUID(),
        displayName: String,
        originalFileName: String,
        storedFileName: String,
        colorIndex: Int,
        startTime: Date,
        endTime: Date,
        pointCount: Int,
        distance: Double,
        addedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.colorIndex = colorIndex
        self.startTime = startTime
        self.endTime = endTime
        self.pointCount = pointCount
        self.distance = distance
        self.addedAt = addedAt
    }
}

public enum GeoshopSchema {
    public static let models: [any PersistentModel.Type] = [Project.self, TrackFile.self]

    /// 디스크(또는 `inMemory`) 저장소를 연다. `url`이 nil이면 SwiftData 기본 위치.
    public static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
