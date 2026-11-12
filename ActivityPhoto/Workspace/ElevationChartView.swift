import Charts
import GeoshopCore
import SwiftUI

/// 고도표 (기획서 §5). x축은 누적 거리(기본) 또는 시각.
/// 세그먼트마다 선을 따로 그려 트랙 사이 공백을 잇지 않는다.
struct ElevationChartView: View {
    @Bindable var workspace: TrackWorkspace
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("고도").font(.headline)
                if workspace.elevationRange == nil {
                    Text("GPX에 고도 정보가 없습니다").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("가로축", selection: $workspace.axis) {
                    ForEach(TrackWorkspace.ProfileAxis.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch workspace.axis {
            case .distance:
                ProfileChart(
                    workspace: workspace,
                    timeZone: timeZone,
                    xLabel: "거리",
                    x: { $0.distance },
                    locationX: { $0.distance },
                    domain: 0...max(workspace.timeline.totalDistance, 1),
                    locationAt: { workspace.timeline.location(atDistance: $0) },
                    axisLabel: { formatDistance($0) }
                )
            case .time:
                let start = workspace.timeline.startTime ?? .now
                let end = max(workspace.timeline.endTime ?? start, start.addingTimeInterval(60))
                ProfileChart(
                    workspace: workspace,
                    timeZone: timeZone,
                    xLabel: "시각",
                    x: { $0.date },
                    locationX: { $0.date },
                    domain: start...end,
                    locationAt: { workspace.timeline.location(at: $0) },
                    axisLabel: { $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)) }
                )
            }
        }
        .padding(12)
    }
}

private struct ProfileChart<X: Plottable & Comparable>: View {
    let workspace: TrackWorkspace
    let timeZone: TimeZone
    let xLabel: String
    let x: (ProfileSample) -> X
    let locationX: (TrackLocation) -> X
    let domain: ClosedRange<X>
    let locationAt: (X) -> TrackLocation?
    let axisLabel: (X) -> String

    private var yDomain: ClosedRange<Double> {
        guard let range = workspace.elevationRange else { return 0...100 }
        let padding = max((range.upperBound - range.lowerBound) * 0.1, 10)
        return (range.lowerBound - padding)...(range.upperBound + padding)
    }

    var body: some View {
        Chart {
            ForEach(workspace.profile) { series in
                let color = TrackPalette.color(workspace.colorIndex(forSegment: series.segmentIndex))
                ForEach(series.samples.indices, id: \.self) { i in
                    let sample = series.samples[i]
                    AreaMark(
                        x: .value(xLabel, x(sample)),
                        yStart: .value("기준", yDomain.lowerBound),
                        yEnd: .value("고도", sample.elevation),
                        series: .value("구간", series.segmentIndex)
                    )
                    .foregroundStyle(color.opacity(0.15))
                    LineMark(
                        x: .value(xLabel, x(sample)),
                        y: .value("고도", sample.elevation),
                        series: .value("구간", series.segmentIndex)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            if let pinned = workspace.pinned {
                RuleMark(x: .value(xLabel, locationX(pinned)))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            if let hovered = workspace.hovered {
                RuleMark(x: .value(xLabel, locationX(hovered)))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if workspace.hoverSource == .chart {
                            LocationBadge(location: hovered, timeZone: timeZone)
                        }
                    }
                if let elevation = hovered.elevation {
                    PointMark(x: .value(xLabel, locationX(hovered)), y: .value("고도", elevation))
                        .foregroundStyle(TrackPalette.color(workspace.colorIndex(forSegment: hovered.segmentIndex)))
                        .symbolSize(60)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(X.self) { Text(axisLabel(v)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v)) m") }
                }
            }
        }
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            workspace.hover(location(at: point, proxy: proxy, geometry: geometry), from: .chart)
                        case .ended:
                            workspace.endHover(from: .chart)
                        }
                    }
                    .onTapGesture { point in
                        workspace.pin(location(at: point, proxy: proxy, geometry: geometry))
                    }
            }
        }
    }

    private func location(at point: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> TrackLocation? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        guard frame.minX...frame.maxX ~= point.x else { return nil }
        guard let value = proxy.value(atX: point.x - frame.minX, as: X.self) else { return nil }
        return locationAt(value)
    }
}
