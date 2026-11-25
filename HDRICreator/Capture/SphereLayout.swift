import Foundation
import simd

/// Where a capture sits in the 28-position layout.
enum TargetKind: String, Codable {
    case zenith, upperRing, middleRing, lowerRing, nadir, supplemental
    var label: String {
        switch self {
        case .zenith: return "Zenith"
        case .upperRing: return "Upper ring"
        case .middleRing: return "Horizon ring"
        case .lowerRing: return "Lower ring"
        case .nadir: return "Nadir"
        case .supplemental: return "Supplemental"
        }
    }
}

/// One aiming target. Angles in degrees: azimuth clockwise from the start heading, elevation up from the horizon.
struct CaptureTarget: Identifiable, Codable, Equatable {
    let id: Int                // 0...27, also the capture order
    let kind: TargetKind
    let azimuth: Double
    let elevation: Double

    /// Unit view direction in the CoreMotion reference frame (x east, y north, z up) once azimuth 0 = start heading.
    var direction: SIMD3<Double> { SphereLayout.direction(azimuth: azimuth, elevation: elevation) }
    var title: String { "\(id + 1) / \(SphereLayout.targetCount)  \(kind.label)" }
}

/// The mathematically defined 28-position layout.
///
/// * 1 zenith (elevation +90)
/// * 8 upper ring at +e1, azimuths 22.5 + 45k   (offset half a step so frames interlock with the horizon ring)
/// * 8 horizon ring at 0, azimuths 45k
/// * 8 lower ring at -e1, azimuths 22.5 + 45k
/// * 1 nadir (elevation -90)
/// * 2 supplementals, chosen greedily to cover whatever the first 26 leave thinnest.
///
/// e1 = 0.8 * vertical FOV (clamped), so neighbouring rows overlap by about 20% of the frame height. The camera is
/// assumed to be held in landscape, so the horizontal FOV spans the 45 degree azimuth step with margin.
struct SphereLayout {
    static let targetCount = 28
    let horizontalFOV: Double
    let verticalFOV: Double
    let ringElevation: Double
    let targets: [CaptureTarget]

    static func direction(azimuth: Double, elevation: Double) -> SIMD3<Double> {
        let a = azimuth * .pi / 180, e = elevation * .pi / 180
        return SIMD3(sin(a) * cos(e), cos(a) * cos(e), sin(e))
    }

    /// Orthonormal camera frame (right, up, forward) for a view direction, landscape, horizon level. Poles use azimuth as roll reference.
    static func frame(azimuth: Double, elevation: Double) -> (right: SIMD3<Double>, up: SIMD3<Double>, forward: SIMD3<Double>) {
        let f = direction(azimuth: azimuth, elevation: elevation)
        let a = azimuth * .pi / 180
        var right = simd_normalize(simd_cross(f, SIMD3(0, 0, 1)))        // east-ish for horizontal views
        if abs(f.z) > 0.999 { right = SIMD3(cos(a), -sin(a), 0) }
        if right.x.isNaN { right = SIMD3(1, 0, 0) }
        let up = simd_cross(right, f)
        return (right, up, f)
    }

    /// True when `dir` lies inside the frame for (azimuth, elevation) shrunk by `shrink` (1 = full frame).
    static func covers(azimuth: Double, elevation: Double, dir: SIMD3<Double>, hFOV: Double, vFOV: Double, shrink: Double = 1) -> Bool {
        let fr = frame(azimuth: azimuth, elevation: elevation)
        let z = simd_dot(dir, fr.forward)
        guard z > 0.05 else { return false }
        let x = simd_dot(dir, fr.right) / z, y = simd_dot(dir, fr.up) / z
        return abs(x) < tan(hFOV * .pi / 360) * shrink && abs(y) < tan(vFOV * .pi / 360) * shrink
    }

    /// Roughly uniform points on the sphere (Fibonacci lattice), used for coverage statistics.
    static func fibonacciSphere(_ n: Int) -> [SIMD3<Double>] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let z = 1 - 2 * (Double(i) + 0.5) / Double(n)
            let r = (1 - z * z).squareRoot()
            let t = golden * Double(i)
            return SIMD3(r * cos(t), r * sin(t), z)
        }
    }

    init(horizontalFOV: Double = 67.4, verticalFOV: Double? = nil) {
        let v = verticalFOV ?? (2 * atan(tan(horizontalFOV * .pi / 360) * 3 / 4) * 180 / .pi)   // 4:3 photo
        self.horizontalFOV = horizontalFOV
        self.verticalFOV = v
        let e1 = min(55, max(30, 0.8 * v))
        ringElevation = e1

        var t: [(TargetKind, Double, Double)] = []
        for k in 0..<8 { t.append((.middleRing, 45.0 * Double(k), 0)) }
        for k in 0..<8 { t.append((.upperRing, 45.0 * Double(k) + 22.5, e1)) }
        for k in 0..<8 { t.append((.lowerRing, 45.0 * Double(k) + 22.5, -e1)) }
        t.append((.zenith, 0, 90))
        t.append((.nadir, 0, -90))

        // Two supplementals: greedily cover samples that the first 26 frames cover zero or one times.
        let samples = SphereLayout.fibonacciSphere(3000)
        var count = [Int](repeating: 0, count: samples.count)
        for (_, az, el) in t {
            for (i, s) in samples.enumerated() where SphereLayout.covers(azimuth: az, elevation: el, dir: s, hFOV: horizontalFOV, vFOV: v) { count[i] += 1 }
        }
        var candidates: [(Double, Double)] = []
        for el in stride(from: -80.0, through: 80.0, by: 10.0) { for az in stride(from: 0.0, to: 360.0, by: 15.0) { candidates.append((az, el)) } }
        for _ in 0..<2 {
            var best = (az: 0.0, el: 0.0), bestScore = -1
            for c in candidates {
                var score = 0
                for (i, s) in samples.enumerated() where SphereLayout.covers(azimuth: c.0, elevation: c.1, dir: s, hFOV: horizontalFOV, vFOV: v) {
                    score += count[i] == 0 ? 1000 : (count[i] == 1 ? 1 : 0)
                }
                if score > bestScore { bestScore = score; best = (c.0, c.1) }
            }
            for (i, s) in samples.enumerated() where SphereLayout.covers(azimuth: best.az, elevation: best.el, dir: s, hFOV: horizontalFOV, vFOV: v) { count[i] += 1 }
            t.append((.supplemental, best.az, best.el))
        }
        targets = t.enumerated().map { CaptureTarget(id: $0.offset, kind: $0.element.0, azimuth: $0.element.1, elevation: $0.element.2) }
    }

    /// Fraction (0...1) of the sphere inside at least one of the frames of `ids`.
    func coverage(of ids: Set<Int>, samples: [SIMD3<Double>]) -> Double {
        guard !ids.isEmpty, !samples.isEmpty else { return 0 }
        let chosen = targets.filter { ids.contains($0.id) }
        var hit = 0
        for s in samples where chosen.contains(where: { SphereLayout.covers(azimuth: $0.azimuth, elevation: $0.elevation, dir: s, hFOV: horizontalFOV, vFOV: verticalFOV) }) { hit += 1 }
        return Double(hit) / Double(samples.count)
    }
}
