import SwiftUI
import simd

/// Live 3D guide sphere. Drawn with an orthographic projection from the camera's point of view: the view rotates with the
/// phone so the current target drifts toward the centre crosshair as you aim.
struct SphereGuideView: View {
    let targets: [CaptureTarget]
    let captured: Set<Int>
    let skipped: Set<Int>
    let currentID: Int?
    let azimuth: Double
    let elevation: Double
    let aligned: Bool

    @State private var pulse = false

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 6
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.hairline.opacity(2)), lineWidth: 1)

            // Camera basis: forward looks at the sphere centre from the inside, so points in front are drawn at the centre.
            let fr = SphereLayout.frame(azimuth: azimuth, elevation: elevation)
            func project(_ d: SIMD3<Double>) -> (CGPoint, Double) {
                let x = simd_dot(d, fr.right), y = simd_dot(d, fr.up), z = simd_dot(d, fr.forward)
                // z > 0 : in front. Use angular (azimuthal-equidistant) mapping so the full sphere fits the disc.
                let theta = acos(max(-1, min(1, z)))                  // 0 at centre ... pi at the back
                let rho = theta / .pi
                let n = (x * x + y * y).squareRoot()
                let ux = n > 1e-9 ? x / n : 0, uy = n > 1e-9 ? y / n : 0
                return (CGPoint(x: c.x + CGFloat(ux * rho) * r, y: c.y - CGFloat(uy * rho) * r), z)
            }
            // Rings of reference every 30 degrees of angular distance.
            for k in 1...5 {
                let rr = r * CGFloat(k) / 6
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(Theme.hairline), lineWidth: 0.5)
            }
            for t in targets {
                let (p, z) = project(t.direction)
                let back = z < 0
                let isCur = t.id == currentID
                let done = captured.contains(t.id), skip = skipped.contains(t.id)
                let rad: CGFloat = isCur ? 9 : 6
                let rect = CGRect(x: p.x - rad, y: p.y - rad, width: 2 * rad, height: 2 * rad)
                let alpha = back ? 0.35 : 1.0
                if done { ctx.fill(Path(ellipseIn: rect), with: .color(Theme.good.opacity(alpha))) }
                else if skip { ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.warn.opacity(alpha)), lineWidth: 1.5) }
                else if isCur {
                    ctx.fill(Path(ellipseIn: rect), with: .color((aligned ? Theme.good : Theme.accent).opacity(0.9)))
                    let halo = rect.insetBy(dx: pulse ? -7 : -3, dy: pulse ? -7 : -3)
                    ctx.stroke(Path(ellipseIn: halo), with: .color(Theme.accent.opacity(pulse ? 0.15 : 0.5)), lineWidth: 1.5)
                } else { ctx.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.45 * alpha)), lineWidth: 1) }
            }
            // Crosshair at the camera axis.
            var h = Path(); h.move(to: CGPoint(x: c.x - 8, y: c.y)); h.addLine(to: CGPoint(x: c.x + 8, y: c.y))
            h.move(to: CGPoint(x: c.x, y: c.y - 8)); h.addLine(to: CGPoint(x: c.x, y: c.y + 8))
            ctx.stroke(h, with: .color(.white), lineWidth: 1)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true } }
        .accessibilityLabel("Capture sphere")
    }
}

