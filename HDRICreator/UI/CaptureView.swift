import SwiftUI

struct CaptureView: View {
    @StateObject var vm: CaptureViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSkip = false
    @State private var showLog = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreviewView(camera: vm.camera).ignoresSafeArea()
            overlay
            if let e = vm.camera.error { errorCard(e.localizedDescription) }
            if !vm.motion.available { errorCard("This device has no gyroscope, so guided capture is not possible.") }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { vm.start(); OrientationLock.set(.landscape) }
        .onDisappear { vm.stop(); OrientationLock.set(.all) }
        .alert("Skip this position?", isPresented: $confirmSkip) {
            Button("Skip", role: .destructive) { vm.skipCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The final panorama will have a gap here, and stitching may be less reliable.") }
        .alert(vm.message ?? "", isPresented: Binding(get: { vm.message != nil }, set: { if !$0 { vm.message = nil } })) { Button("OK") {} }
    }

    // MARK: overlay
    private var overlay: some View {
        HStack(spacing: 0) {
            leftColumn.frame(width: 190)
            Spacer()
            guidance
            Spacer()
            rightColumn.frame(width: 150)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }.buttonStyle(GlassButtonStyle())
                Spacer()
            }
            SphereGuideView(targets: vm.targets, captured: vm.captured, skipped: vm.skipped,
                            currentID: vm.current?.id, azimuth: vm.motion.azimuth, elevation: vm.motion.elevation, aligned: vm.aligned)
                .frame(width: 170, height: 170)
                .background(.ultraThinMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(vm.captured.count)/28").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("Coverage \(Int(vm.coverage * 100))%").font(.caption).foregroundStyle(Theme.textSecondary)
                ProgressView(value: Double(vm.captured.count), total: 28).tint(Theme.accent)
            }
            Spacer()
        }
    }

    private var guidance: some View {
        VStack(spacing: 10) {
            Spacer()
            if !vm.started {
                VStack(spacing: 8) {
                    Text("Hold the phone in landscape").font(.headline)
                    Text("Face the direction you want as the start of the panorama, then tap Set Start. Stay in one spot and rotate around the phone's lens, not your body.")
                        .font(.footnote).multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
                    Button("Set Start Heading") { vm.beginSession() }.buttonStyle(PrimaryButtonStyle()).frame(width: 240)
                }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if vm.finished {
                VStack(spacing: 8) {
                    Text("Capture complete").font(.title3.weight(.semibold))
                    Text("\(vm.captured.count) photos, \(vm.skipped.count) skipped").foregroundStyle(Theme.textSecondary)
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).frame(width: 200)
                }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if let t = vm.current {
                statusCard(t)
            }
            Spacer()
            if vm.started, !vm.finished { shutterRow }
        }
    }

    private func statusCard(_ t: CaptureTarget) -> some View {
        let angle = vm.angleToTarget
        return VStack(spacing: 6) {
            Text(t.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text(instruction(t, angle)).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            HStack(spacing: 14) {
                indicator("Aim", vm.aligned ? "OK" : "\(Int(angle))°", vm.aligned ? Theme.good : Theme.accent)
                indicator("Still", vm.motion.isStable ? "OK" : "…", vm.motion.isStable ? Theme.good : Theme.warn)
                indicator("Level", vm.levelOK ? "OK" : "\(Int(abs(vm.motion.rollError)))°", vm.levelOK ? Theme.good : Theme.warn)
                indicator("Az/El", "\(Int(vm.motion.azimuth))°/\(Int(vm.motion.elevation))°", Theme.textSecondary)
            }
        }
        .padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(vm.ready ? Theme.good : Theme.hairline, lineWidth: vm.ready ? 2 : 1))
        .animation(.easeOut(duration: 0.2), value: vm.ready)
    }

    private func indicator(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(title).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
        }.frame(minWidth: 44)
    }

    private func instruction(_ t: CaptureTarget, _ angle: Double) -> String {
        if vm.capturing { return "Capturing…" }
        if vm.ready { return vm.autoCapture ? "Hold still" : "Tap the shutter" }
        if !vm.aligned {
            let dAz = MotionManager.wrap(t.azimuth - vm.motion.azimuth), dEl = t.elevation - vm.motion.elevation
            if abs(t.elevation) > 75 { return t.elevation > 0 ? "Point straight up" : "Point straight down" }
            if abs(dEl) > abs(dAz) * 0.6 { return dEl > 0 ? "Tilt up" : "Tilt down" }
            return dAz > 0 ? "Turn right" : "Turn left"
        }
        if !vm.levelOK { return "Level the horizon" }
        return "Hold still"
    }

    private var shutterRow: some View {
        HStack(spacing: 30) {
            Button("Redo last") { vm.redoPrevious() }.buttonStyle(GlassButtonStyle()).disabled(vm.captured.isEmpty)
            Button { vm.shoot() } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 3).frame(width: 66, height: 66)
                    Circle().fill(vm.ready ? Theme.good : .white).frame(width: 54, height: 54)
                }
            }.disabled(vm.capturing)
            Button("Skip") { confirmSkip = true }.buttonStyle(GlassButtonStyle())
        }.padding(.bottom, 4)
    }

    // MARK: right column: camera controls (only what the hardware supports)
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if vm.camera.lenses.count > 1 {
                HStack(spacing: 6) {
                    ForEach(vm.camera.lenses) { l in
                        Button(l.name) { vm.camera.select(l) }
                            .buttonStyle(GlassButtonStyle())
                            .opacity(vm.camera.selectedLens == l ? 1 : 0.55)
                    }
                }
            }
            Toggle("Auto", isOn: $vm.autoCapture).toggleStyle(.switch).tint(Theme.accent).labelsHidden()
            Text("Auto-capture").font(.caption2).foregroundStyle(Theme.textSecondary)
            Button { vm.camera.lockExposureAndWhiteBalance(!vm.camera.lockedExposure) } label: {
                Label(vm.camera.lockedExposure ? "AE/AWB locked" : "Lock AE/AWB", systemImage: vm.camera.lockedExposure ? "lock.fill" : "lock.open")
            }.buttonStyle(GlassButtonStyle())
            if vm.camera.capabilities.manualFocus {
                Button { vm.camera.lockFocus(!vm.camera.lockedFocus) } label: {
                    Label(vm.camera.lockedFocus ? "Focus locked" : "Lock focus", systemImage: vm.camera.lockedFocus ? "lock.fill" : "scope")
                }.buttonStyle(GlassButtonStyle())
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "ISO %.0f  1/%.0f", vm.camera.iso, vm.camera.exposureSeconds > 0 ? 1 / vm.camera.exposureSeconds : 0))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                if vm.camera.capabilities.maxBias > vm.camera.capabilities.minBias {
                    Slider(value: Binding(get: { Double(vm.camera.exposureOffset) }, set: { vm.camera.setExposureOffset(Float($0)) }),
                           in: Double(vm.camera.capabilities.minBias)...Double(vm.camera.capabilities.maxBias)).tint(Theme.accent).frame(width: 130)
                    Text(String(format: "EV %+.1f", vm.camera.exposureOffset)).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Text(vm.camera.capabilities.rawSupported ? "RAW available" : "RAW not available").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private func errorCard(_ s: String) -> some View {
        Text(s).font(.callout).multilineTextAlignment(.center).padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)).padding(40)
    }
}
