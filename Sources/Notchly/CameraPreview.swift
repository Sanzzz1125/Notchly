import SwiftUI
import AVFoundation

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                if self.session.inputs.isEmpty {
                    guard let dev = AVCaptureDevice.default(for: .video),
                          let input = try? AVCaptureDeviceInput(device: dev),
                          self.session.canAddInput(input) else { return }
                    self.session.addInput(input)
                }
                DispatchQueue.main.async { self.attachLayer() }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    private func attachLayer() {
        guard previewLayer == nil else { return }
        let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspectFill
        l.frame = bounds
        l.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let c = l.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        layer?.addSublayer(l)
        previewLayer = l
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView {
        let v = CameraPreviewView()
        v.start()
        return v
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) {
        nsView.stop()
    }
}
