import CoreMotion
import simd
import Combine

/// Device orientation from CoreMotion, expressed as where the back camera points.
/// Reference frame: x east-ish (arbitrary), y north-ish, z up (xArbitraryZVertical). `headingOffset` makes azimuth 0 = the
/// direction the user was facing when they pressed "set start".
final class MotionManager: ObservableObject {
    @Published private(set) var forward = SIMD3<Double>(0, 1, 0)      // camera optical axis in reference frame
    @Published private(set) var azimuth = 0.0                          // degrees, relative to start heading
    @Published private(set) var elevation = 0.0                        // degrees above horizon
    @Published private(set) var rollError = 0.0                        // degrees the horizon is tilted (landscape hold)
    @Published private(set) var stableFor = 0.0                        // seconds the device has been still
    @Published private(set) var isStable = false
    @Published private(set) var available = true

    private let cm = CMMotionManager()
    private var rawAzimuth = 0.0
    private var headingOffset = 0.0
    private var stillSince: Date?
    /// Rotation-rate threshold (rad/s) below which the device counts as still.
    var stillThreshold = 0.10
    /// Seconds of stillness required for isStable.
    var stableTime = 0.35

    func start() {
        guard cm.isDeviceMotionAvailable else { available = false; return }
        cm.deviceMotionUpdateInterval = 1.0 / 60.0
        cm.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            self.ingest(m)
        }
    }

    func stop() { cm.stopDeviceMotionUpdates() }

    /// Treat the current heading as azimuth 0.
    func setStartHeading() { headingOffset = rawAzimuth; azimuth = 0 }

    private func ingest(_ m: CMDeviceMotion) {
        let r = m.attitude.rotationMatrix
        // CMRotationMatrix maps reference -> device, so reference = R^T * device. Back camera looks along -Z_device.
        let f = SIMD3(-r.m31, -r.m32, -r.m33)
        // Device +Y axis in reference frame; in landscape this is the image's horizontal axis, so its height is the roll error.
        let yAxis = SIMD3(r.m21, r.m22, r.m23)
        forward = f
        elevation = asin(max(-1, min(1, f.z))) * 180 / .pi
        rawAzimuth = atan2(f.x, f.y) * 180 / .pi
        azimuth = MotionManager.wrap(rawAzimuth - headingOffset)
        rollError = asin(max(-1, min(1, yAxis.z))) * 180 / .pi

        let w = m.rotationRate
        let rate = (w.x * w.x + w.y * w.y + w.z * w.z).squareRoot()
        if rate < stillThreshold {
            if stillSince == nil { stillSince = Date() }
            stableFor = Date().timeIntervalSince(stillSince!)
        } else { stillSince = nil; stableFor = 0 }
        isStable = stableFor >= stableTime
    }

    /// Unit view direction of the camera with azimuth measured from the start heading.
    var alignedForward: SIMD3<Double> { SphereLayout.direction(azimuth: azimuth, elevation: elevation) }

    /// Angular distance in degrees from the camera axis to a target.
    func angle(to t: CaptureTarget) -> Double {
        let d = simd_dot(alignedForward, t.direction)
        return acos(max(-1, min(1, d))) * 180 / .pi
    }

    static func wrap(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }; if x < -180 { x += 360 }
        return x
    }
}
