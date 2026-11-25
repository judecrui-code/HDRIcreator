import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraManager

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = camera.session
        v.previewLayer.videoGravity = .resizeAspect      // show the full 4:3 frame that will be captured
        v.backgroundColor = .black
        camera.attach(previewLayer: v.previewLayer)
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
