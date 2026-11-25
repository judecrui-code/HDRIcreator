import SwiftUI
import Combine

/// Ties camera + motion + layout together for one capture session.
final class CaptureViewModel: ObservableObject {
    let camera = CameraManager()
    let motion = MotionManager()
    let store: ProjectStore
    @Published private(set) var project: Project
    @Published private(set) var layout: SphereLayout
    @Published private(set) var currentIndex = 0
    @Published private(set) var captured: Set<Int>
    @Published private(set) var skipped: Set<Int>
    @Published private(set) var coverage = 0.0
    @Published private(set) var capturing = false
    @Published private(set) var aligned = false         // aimed within tolerance
    @Published private(set) var ready = false           // aimed + stable + level
    @Published private(set) var started = false
    @Published var message: String?
    @Published var autoCapture: Bool = UserDefaults.standard.object(forKey: "autoCapture") as? Bool ?? true

    /// Aim tolerance in degrees.
    var tolerance: Double { UserDefaults.standard.object(forKey: "aimTolerance") as? Double ?? 6 }
    private let samples = SphereLayout.fibonacciSphere(2500)
    private var bag = Set<AnyCancellable>()
    private var lastFire = Date.distantPast

    var targets: [CaptureTarget] { layout.targets }
    var current: CaptureTarget? { currentIndex < targets.count ? targets[currentIndex] : nil }
    var angleToTarget: Double { current.map { motion.angle(to: $0) } ?? 0 }
    var isPole: Bool { abs(current?.elevation ?? 0) > 75 }
    var levelOK: Bool { isPole || abs(motion.rollError) < 4 }
    var finished: Bool { captured.count + skipped.count >= targets.count || current == nil }

    init(project: Project, store: ProjectStore) {
        self.project = project; self.store = store
        layout = SphereLayout(horizontalFOV: project.horizontalFOV)
        captured = Set(project.capturedIDs); skipped = Set(project.skippedIDs)
        currentIndex = layout.targets.firstIndex { !Set(project.capturedIDs).contains($0.id) && !Set(project.skippedIDs).contains($0.id) } ?? layout.targets.count
        coverage = layout.coverage(of: captured, samples: samples)

        // Re-evaluate readiness at motion-update rate.
        motion.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.evaluate() }
        }.store(in: &bag)
        // Rebuild the layout once the real lens FOV is known (only while nothing has been captured, so existing shots stay valid).
        camera.$capabilities.receive(on: DispatchQueue.main).sink { [weak self] caps in
            guard let self, self.captured.isEmpty, abs(caps.horizontalFOV - self.layout.horizontalFOV) > 0.5, caps.horizontalFOV > 20 else { return }
            self.layout = SphereLayout(horizontalFOV: caps.horizontalFOV)
            self.project.horizontalFOV = caps.horizontalFOV
            try? self.store.save(self.project)
        }.store(in: &bag)
        camera.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    func start() { camera.start(); motion.start() }
    func stop() { camera.stop(); motion.stop() }

    func beginSession() { motion.setStartHeading(); started = true; Haptics.tap() }

    private func evaluate() {
        guard started, let _ = current else { aligned = false; ready = false; return }
        let a = angleToTarget <= tolerance
        let r = a && motion.isStable && levelOK && !capturing
        if a != aligned { aligned = a; if a { Haptics.tap() } }
        ready = r
        if r && autoCapture && Date().timeIntervalSince(lastFire) > 1.2 { shoot() }
    }

    func shoot() {
        guard !capturing, let t = current else { return }
        capturing = true; lastFire = Date()
        camera.capturePhoto { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.capturing = false
                switch result {
                case .success(let data):
                    do {
                        try self.store.writeShot(data, project: self.project, id: t.id)
                        self.captured.insert(t.id); self.skipped.remove(t.id)
                        self.persist(); Haptics.capture()
                        self.advance()
                    } catch { self.message = "Could not save photo: \(error.localizedDescription)" }
                case .failure(let e): self.message = e.localizedDescription; Haptics.warning()
                }
            }
        }
    }

    func skipCurrent() {
        guard let t = current else { return }
        skipped.insert(t.id); persist(); Haptics.warning()
        message = "Skipped \(t.kind.label.lowercased()) position \(t.id + 1). Gaps in coverage will appear in the final panorama."
        advance()
    }

    /// Go back to retake a position (no duplicate: the old file is replaced).
    func redo(_ id: Int) {
        guard let i = targets.firstIndex(where: { $0.id == id }) else { return }
        captured.remove(id); skipped.remove(id); currentIndex = i; persist()
    }
    func redoPrevious() { if let last = captured.union(skipped).filter({ $0 < (current?.id ?? targets.count) }).max() { redo(last) } }

    private func advance() {
        coverage = layout.coverage(of: captured, samples: samples)
        currentIndex = targets.firstIndex { !captured.contains($0.id) && !skipped.contains($0.id) } ?? targets.count
        if finished { project.status = .captured; try? store.save(project); Haptics.success() }
    }

    private func persist() {
        project.capturedIDs = captured.sorted(); project.skippedIDs = skipped.sorted()
        try? store.save(project)
    }
}
extension CaptureViewModel: Identifiable {}
