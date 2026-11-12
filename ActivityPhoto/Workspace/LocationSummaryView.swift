import GeoshopCore
import SwiftUI

/// 트랙 위 지점 요약: 시각 · 고도 · 누적거리 (기획서 §4.3 툴팁).
struct LocationSummaryView: View {
    let location: TrackLocation
    let timeZone: TimeZone
    var showsCoordinate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(location.date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, timeZone: timeZone)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            HStack(spacing: 8) {
                if let elevation = location.elevation {
                    Label("\(Int(elevation.rounded())) m", systemImage: "mountain.2")
                }
                Label(formatDistance(location.distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            if showsCoordinate {
                Text(String(format: "%.6f, %.6f", location.latitude, location.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

/// 지도·고도표 위에 띄우는 작은 카드.
struct LocationBadge: View {
    let location: TrackLocation
    let timeZone: TimeZone

    var body: some View {
        LocationSummaryView(location: location, timeZone: timeZone)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
}
