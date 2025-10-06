
import SwiftUI
import AVFoundation
import Combine

final class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var current = RGB(r:128,g:128,b:128)
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cam.queue")

    func start() {
        queue.async {
            guard !self.session.isRunning else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            guard
                let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: dev),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            let out = AVCaptureVideoDataOutput()
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            out.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.canAddOutput(out) { self.session.addOutput(out) }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            DispatchQueue.main.async { self.session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let base = CVPixelBufferGetBaseAddress(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        if let base = base {
            let x = w/2, y = h/2
            let ptr = base.advanced(by: y*bpr + x*4).assumingMemoryBound(to: UInt8.self)
            let b = Int(ptr[0]), g = Int(ptr[1]), r = Int(ptr[2])
            DispatchQueue.main.async { self.current = RGB(r:r,g:g,b:b) }
        }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspectFill
        v.layer.addSublayer(l)
        DispatchQueue.main.async { l.frame = v.bounds }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.layer.sublayers?.first?.frame = uiView.bounds
    }
}

struct CameraScreen: View {
    @EnvironmentObject var store: StoreVM
    @StateObject private var cam = CameraModel()
    @State private var palette:[RGB] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CameraPreview(session: cam.session)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottomLeading) {
                        InfoCard(rgb: cam.current).padding(10)
                    }

                HStack(spacing: 12) {
                    Button {
                        let img = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { ctx in
                            UIColor(red: CGFloat(cam.current.r)/255, green: CGFloat(cam.current.g)/255, blue: CGFloat(cam.current.b)/255, alpha: 1).setFill()
                            UIBezierPath(rect: CGRect(x:0,y:0,width:80,height:80)).fill()
                        }
                        palette = KMeans.palette(from: img, k: 5)
                    } label: {
                        Label("Capture Palette", systemImage: "camera.metering.center.weighted")
                    }.buttonStyle(.borderedProminent)

                    Button { store.showPaywall = true } label: { Text("Unlock Pro") }
                        .buttonStyle(.bordered)
                }

                if !palette.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                                SwatchView(c: c)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Camera")
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
        .sheet(isPresented: $store.showPaywall) { PaywallView().environmentObject(store) }
    }
}

struct InfoCard: View {
    let rgb: RGB
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8).fill(Color(rgb.uiColor)).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(rgb.hex).font(.headline)
                Text(rgb.rgbText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SwatchView: View {
    let c: RGB
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(c.uiColor))
                .frame(width: 76, height: 76)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.25), lineWidth: 1))
            Text(c.hex).font(.caption2)
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
