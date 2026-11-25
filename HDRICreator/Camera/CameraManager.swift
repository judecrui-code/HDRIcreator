import AVFoundation
import UIKit

struct CameraLens: Identifiable, Hashable {
    let id: String
    let name: String
    let type: AVCaptureDevice.DeviceType
    var device: AVCaptureDevice? { AVCaptureDevice(uniqueID: id) }
}

/// What the current device/format can actually do. UI hides everything that is false.
struct CameraCapabilities {
    var minISO: Float = 0, maxISO: Float = 0
    var minExposure = CMTime.zero, maxExposure = CMTime.zero
    var minBias: Float = 0, maxBias: Float = 0
    var manualExposure = false
    var manualFocus = false
    var lockedWhiteBalance = false
    var stabilization = false
    var rawSupported = false
    var horizontalFOV = 67.4
    var photoDimensions: [CMVideoDimensions] = []
}

enum CameraError: LocalizedError {
    case denied, noCamera, configuration(String), capture(String)
    var errorDescription: String? {
        switch self {
        case .denied: return "Camera access is off. Enable it in Settings > HDRI Creator."
        case .noCamera: return "No back camera is available on this device."
        case .configuration(let s): return "Camera setup failed: \(s)"
        case .capture(let s): return "Capture failed: \(s)"
        }
    }
}

/// Owns the AVCaptureSession. All configuration happens on `queue`; published state is updated on main.
final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationObserver: NSKeyValueObservation?
    private var pending: [Int64: (Result<Data, Error>) -> Void] = [:]

    @Published private(set) var lenses: [CameraLens] = []
    @Published private(set) var selectedLens: CameraLens?
    @Published private(set) var capabilities = CameraCapabilities()
    @Published private(set) var running = false
    @Published private(set) var iso: Float = 0
    @Published private(set) var exposureSeconds: Double = 0
    @Published private(set) var exposureOffset: Float = 0
    @Published private(set) var lockedExposure = false
    @Published private(set) var lockedFocus = false
    @Published var error: CameraError?

    // MARK: lifecycle
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { ok ? self.configureAndRun() : (self.error = .denied) }
            }
        default: error = .denied
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.running = false }
        }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
                mediaType: .video, position: .back)
            let found = discovery.devices.map { CameraLens(id: $0.uniqueID, name: CameraManager.name(for: $0.deviceType), type: $0.deviceType) }
            guard !found.isEmpty else { DispatchQueue.main.async { self.error = .noCamera }; return }
            let main = found.first { $0.type == .builtInWideAngleCamera } ?? found[0]
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            self.session.commitConfiguration()
            DispatchQueue.main.async { self.lenses = found }
            self.apply(lens: main)
            self.session.startRunning()
            DispatchQueue.main.async { self.running = self.session.isRunning }
        }
    }

    static func name(for t: AVCaptureDevice.DeviceType) -> String {
        switch t {
        case .builtInUltraWideCamera: return "0.5x"
        case .builtInTelephotoCamera: return "Tele"
        default: return "1x"
        }
    }

    // MARK: lens
    func select(_ lens: CameraLens) { queue.async { [weak self] in self?.apply(lens: lens) } }

    private func apply(lens: CameraLens) {
        guard let device = lens.device else { return }
        session.beginConfiguration()
        if let old = input { session.removeInput(old) }
        do {
            let new = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(new) { session.addInput(new); input = new }
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = .configuration(error.localizedDescription) }
            return
        }
        session.commitConfiguration()
        // Pick the largest 4:3 photo format.
        if let fmt = device.formats.filter({ f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return abs(Double(d.width) / Double(d.height) - 4.0 / 3.0) < 0.01
        }).max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) {
            try? device.lockForConfiguration()
            device.activeFormat = fmt
            device.unlockForConfiguration()
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
        var caps = CameraCapabilities()
        let f = device.activeFormat
        caps.minISO = f.minISO; caps.maxISO = f.maxISO
        caps.minExposure = f.minExposureDuration; caps.maxExposure = f.maxExposureDuration
        caps.minBias = device.minExposureTargetBias; caps.maxBias = device.maxExposureTargetBias
        caps.manualExposure = device.isExposureModeSupported(.custom)
        caps.manualFocus = device.isLockingFocusWithCustomLensPositionSupported
        caps.lockedWhiteBalance = device.isWhiteBalanceModeSupported(.locked)
        caps.stabilization = f.isVideoStabilizationModeSupported(.auto)
        caps.rawSupported = photoOutput.availableRawPhotoPixelFormatTypes.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        caps.horizontalFOV = Double(f.videoFieldOfView)
        caps.photoDimensions = f.supportedMaxPhotoDimensions
        // Orientation tracking for preview and capture.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        rotationObserver = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] c, _ in
            self?.previewLayer?.connection?.videoRotationAngle = c.videoRotationAngleForHorizonLevelPreview
        }
        DispatchQueue.main.async {
            self.selectedLens = lens
            self.capabilities = caps
            self.lockedExposure = false; self.lockedFocus = false
            self.iso = device.iso; self.exposureSeconds = device.exposureDuration.seconds
        }
    }

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        queue.async { [weak self] in
            guard let self, let d = self.input?.device else { return }
            let c = AVCaptureDevice.RotationCoordinator(device: d, previewLayer: previewLayer)
            self.rotation = c
            self.rotationObserver = c.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { c, _ in
                previewLayer.connection?.videoRotationAngle = c.videoRotationAngleForHorizonLevelPreview
            }
        }
    }

    // MARK: exposure / focus
    func setExposureOffset(_ ev: Float) {
        withDevice { d in
            let v = max(d.minExposureTargetBias, min(d.maxExposureTargetBias, ev))
            d.setExposureTargetBias(v) { _ in }
            DispatchQueue.main.async { self.exposureOffset = v }
        }
    }

    /// Lock exposure (and white balance) at the current auto values, so every one of the 28 positions uses the same settings.
    func lockExposureAndWhiteBalance(_ on: Bool) {
        withDevice { d in
            if on {
                if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
                if d.isWhiteBalanceModeSupported(.locked) { d.whiteBalanceMode = .locked }
            } else {
                if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
            }
            DispatchQueue.main.async { self.lockedExposure = on }
        }
    }

    func lockFocus(_ on: Bool) {
        withDevice { d in
            if on { if d.isFocusModeSupported(.locked) { d.focusMode = .locked } }
            else if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            DispatchQueue.main.async { self.lockedFocus = on }
        }
    }

    func setManualExposure(iso: Float, seconds: Double) {
        withDevice { d in
            guard d.isExposureModeSupported(.custom) else { return }
            let f = d.activeFormat
            let duration = CMTime(seconds: max(f.minExposureDuration.seconds, min(f.maxExposureDuration.seconds, seconds)), preferredTimescale: 1_000_000_000)
            d.setExposureModeCustom(duration: duration, iso: max(f.minISO, min(f.maxISO, iso))) { _ in }
            DispatchQueue.main.async { self.lockedExposure = true; self.iso = iso; self.exposureSeconds = duration.seconds }
        }
    }

    private func withDevice(_ body: @escaping (AVCaptureDevice) -> Void) {
        queue.async { [weak self] in
            guard let d = self?.input?.device else { return }
            do { try d.lockForConfiguration(); body(d); d.unlockForConfiguration() }
            catch { DispatchQueue.main.async { self?.error = .configuration(error.localizedDescription) } }
        }
    }

    // MARK: capture
    /// Capture one photo as HEIC/JPEG data. (Bracketed capture and RAW come in the next stage.)
    func capturePhoto(completion: @escaping (Result<Data, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            if let c = self.photoOutput.connection(with: .video), let r = self.rotation {
                c.videoRotationAngle = r.videoRotationAngleForHorizonLevelCapture
            }
            self.pending[settings.uniqueID] = completion
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        queue.async { [weak self] in
            guard let self, let done = self.pending.removeValue(forKey: id) else { return }
            if let error { done(.failure(CameraError.capture(error.localizedDescription))) }
            else if let data = photo.fileDataRepresentation() { done(.success(data)) }
            else { done(.failure(CameraError.capture("no image data"))) }
        }
    }
}
