import Foundation

/// 고도표에 그릴 점 하나.
public struct ProfileSample: Sendable, Hashable {
    /// 타임라인 누적 거리 (미터).
    public var distance: Double
    public var date: Date
    public var elevation: Double
}

/// 고도표의 선 하나 (세그먼트 하나). 세그먼트 사이는 선을 잇지 않는다.
public struct ProfileSeries: Sendable, Hashable, Identifiable {
    public var segmentIndex: Int
    public var samples: [ProfileSample]
    public var id: Int { segmentIndex }
}

/// 지도 표시용 영역.
public struct CoordinateBounds: Sendable, Hashable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double
}

extension TrackTimeline {
    /// 고도표용으로 줄인 점들 (기획서 §5).
    ///
    /// 세그먼트마다 포인트 수에 비례해 예산을 나누고, 구간(bucket)마다 고도 최저·최고 점을 남겨
    /// 봉우리와 골짜기가 사라지지 않게 한다. 세그먼트의 처음과 끝 점은 항상 남는다.
    /// 고도가 없는 포인트는 건너뛴다.
    public func elevationProfile(maxSamples: Int = 2_000) -> [ProfileSeries] {
        let totalPoints = segments.reduce(0) { $0 + $1.points.count }
        guard totalPoints > 0 else { return [] }

        return segments.enumerated().compactMap { segmentIndex, segment in
            var samples: [ProfileSample] = []
            samples.reserveCapacity(segment.points.count)
            for (i, point) in segment.points.enumerated() {
                guard let elevation = point.elevation else { continue }
                samples.append(ProfileSample(distance: segment.cumulativeDistances[i], date: point.time, elevation: elevation))
            }
            guard !samples.isEmpty else { return nil }

            let budget = max(4, maxSamples * segment.points.count / totalPoints)
            return ProfileSeries(segmentIndex: segmentIndex, samples: Self.downsample(samples, budget: budget))
        }
    }

    static func downsample(_ samples: [ProfileSample], budget: Int) -> [ProfileSample] {
        guard samples.count > budget, budget >= 4 else { return samples }
        let first = samples[0], last = samples[samples.count - 1]
        let inner = samples[1..<(samples.count - 1)]
        let bucketCount = (budget - 2) / 2
        let bucketSize = Double(inner.count) / Double(bucketCount)

        var result: [ProfileSample] = [first]
        result.reserveCapacity(budget)
        for b in 0..<bucketCount {
            let lower = inner.startIndex + Int(Double(b) * bucketSize)
            let upper = min(inner.startIndex + Int(Double(b + 1) * bucketSize), inner.endIndex)
            guard lower < upper else { continue }
            var minIndex = lower, maxIndex = lower
            for i in lower..<upper {
                if samples[i].elevation < samples[minIndex].elevation { minIndex = i }
                if samples[i].elevation > samples[maxIndex].elevation { maxIndex = i }
            }
            if minIndex == maxIndex {
                result.append(samples[minIndex])
            } else {
                result.append(samples[min(minIndex, maxIndex)])
                result.append(samples[max(minIndex, maxIndex)])
            }
        }
        result.append(last)
        return result
    }

    /// 지도 선 그리기용으로 줄인 포인트. 직전에 남긴 점에서 `minimumSpacing`(미터)보다 가까운 점은 건너뛴다.
    /// 처음과 끝 점은 항상 남는다.
    public func displayPath(segmentIndex: Int, minimumSpacing: Double = 5) -> [TrackPoint] {
        let points = segments[segmentIndex].points
        guard points.count > 2 else { return points }
        var result: [TrackPoint] = [points[0]]
        for point in points[1..<(points.count - 1)] where Geo.distance(result[result.count - 1], point) >= minimumSpacing {
            result.append(point)
        }
        result.append(points[points.count - 1])
        return result
    }

    /// 고도 최저·최고 (고도 정보가 없으면 nil).
    public var elevationRange: ClosedRange<Double>? {
        var low = Double.infinity, high = -Double.infinity
        for segment in segments {
            for point in segment.points {
                guard let e = point.elevation else { continue }
                low = min(low, e)
                high = max(high, e)
            }
        }
        return low <= high ? low...high : nil
    }

    public var bounds: CoordinateBounds? {
        guard !segments.isEmpty else { return nil }
        var b = CoordinateBounds(minLatitude: 90, maxLatitude: -90, minLongitude: 180, maxLongitude: -180)
        for segment in segments {
            for point in segment.points {
                b.minLatitude = min(b.minLatitude, point.latitude)
                b.maxLatitude = max(b.maxLatitude, point.latitude)
                b.minLongitude = min(b.minLongitude, point.longitude)
                b.maxLongitude = max(b.maxLongitude, point.longitude)
            }
        }
        return b
    }

    /// 반경 안에서 클릭 지점에 가장 가까운 트랙 위 지점 (마우스 호버용). 후보 묶음 없이 하나만.
    public func nearestLocation(latitude: Double, longitude: Double, radius: Double) -> TrackLocation? {
        snapCandidates(latitude: latitude, longitude: longitude, radius: radius, minimumTimeSeparation: .infinity)
            .first?.location
    }
}
