import SwiftUI
import AVFoundation
import UIKit
import CoreImage
import CoreGraphics
import Combine

// MARK: - Engine + helpers

extension UIImage {
    func color(at point: CGPoint) -> UIColor? {
        guard let cg = cgImage,
              let provider = cg.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bytesPerPixel = 4, bytesPerRow = cg.bytesPerRow
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height else { return nil }
        let off = y * bytesPerRow + x * bytesPerPixel
        let r = CGFloat(ptr[off]) / 255.0
        let g = CGFloat(ptr[off + 1]) / 255.0
        let b = CGFloat(ptr[off + 2]) / 255.0
        let a = CGFloat(ptr[off + 3]) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

// MARK: - Camera Engine

@MainActor
final class CameraEngine: NSObject, ObservableObject {
    @Published var currentRGB: RGB = RGB(r: 128, g: 128, b: 128)
    @Published var lastFrame: UIImage?
    @Published var torchOn = false
    @Published var isRunning = false
    @Published var isUsingFront = false

    let session = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private let videoOut = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.engine.queue")
    private let ci = CIContext(options: [.workingColorSpace: kCFNull!])

    private var lastFrameTime: CFTimeInterval = 0
    private let frameInterval: CFTimeInterval = 0.14

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else {
            session.commitConfiguration(); return
        }
        session.addInput(input)
        videoInput = input
        isUsingFront = false

        videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOut.alwaysDiscardsLateVideoFrames = true
        videoOut.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOut) { session.addOutput(videoOut) }

        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        queue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        queue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    func activeDevice() -> AVCaptureDevice? { videoInput?.device }

    func setZoom(factor: CGFloat) {
        guard let dev = videoInput?.device else { return }
        do {
            try dev.lockForConfiguration()
            let clamped = max(1.0, min(factor, dev.activeFormat.videoMaxZoomFactor))
            dev.videoZoomFactor = clamped
            dev.unlockForConfiguration()
        } catch { print("Zoom:", error.localizedDescription) }
    }

    func setTorch(_ on: Bool) {
        guard let dev = videoInput?.device, dev.hasTorch else { return }
        do {
            try dev.lockForConfiguration()
            dev.torchMode = on ? .on : .off
            dev.unlockForConfiguration()
            torchOn = on
        } catch { print("Torch:", error.localizedDescription) }
    }

    func switchCamera() {
        guard let current = videoInput else { return }
        session.beginConfiguration()
        session.removeInput(current)
        let newPos: AVCaptureDevice.Position = (current.device.position == .back) ? .front : .back
        guard let newDev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPos),
              let newInput = try? AVCaptureDeviceInput(device: newDev),
              session.canAddInput(newInput) else {
            session.addInput(current); session.commitConfiguration(); return
        }
        session.addInput(newInput)
        videoInput = newInput
        isUsingFront = (newPos == .front)
        session.commitConfiguration()
    }

    var brightness: Double {
        let r = Double(currentRGB.r)/255, g = Double(currentRGB.g)/255, b = Double(currentRGB.b)/255
        return 0.2126*r + 0.7152*g + 0.0722*b
    }
}

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let x = w/2, y = h/2
            let px = base.advanced(by: y*bpr + x*4)
            let b = Int(px.load(fromByteOffset: 0, as: UInt8.self))
            let g = Int(px.load(fromByteOffset: 1, as: UInt8.self))
            let r = Int(px.load(fromByteOffset: 2, as: UInt8.self))
            Task { @MainActor in self.currentRGB = RGB(r: r, g: g, b: b) }
        }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= frameInterval else { return }
        lastFrameTime = now
        let ciImage = CIImage(cvImageBuffer: pb)
        if let cg = ci.createCGImage(ciImage, from: ciImage.extent) {
            let img = UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .right)
            Task { @MainActor in self.lastFrame = img }
        }
    }
}

// MARK: - Preview View

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var engine: CameraEngine

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoLayer.session = engine.session
        v.videoLayer.videoGravity = .resizeAspectFill

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPinch(_:)))
        v.addGestureRecognizer(pinch)
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject {
        let engine: CameraEngine
        init(engine: CameraEngine) { self.engine = engine }
        private var baseZoom: CGFloat = 1.0

        @objc func onPinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: baseZoom = engine.activeDevice()?.videoZoomFactor ?? 1.0
            case .changed, .ended:
                engine.setZoom(factor: baseZoom * g.scale)
            default: break
            }
        }
    }
}

// MARK: - Toast

enum ToastKind { case success, info, error }

struct ToastBanner: View {
    let title: String
    let message: String
    let kind: ToastKind

    private var tint: Color {
        switch kind {
        case .success: return .green
        case .info:    return .blue
        case .error:   return .red
        }
    }

    private var symbol: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundColor(tint)
                .font(.title3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Camera Screen

struct CameraScreen: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @StateObject private var engine = CameraEngine()

    @State private var likedPulse = false
    @State private var copiedPulse = false
    @State private var flash = false

    @State private var toastMessage: String? = nil

    @State private var matches: MatchesPayload? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                // Top bar
            HStack {
                let ok = engine.brightness > 0.45
                Label(ok ? "Good Light" : "Low Light",
                    systemImage: ok ? "lightbulb.fill" : "cloud.fill")
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .foregroundStyle(ok ? .green : .orange)

                Spacer()

                HStack(spacing: 10) {
                    // Torch button
                    let showTorch = (engine.activeDevice()?.hasTorch ?? false) && !engine.isUsingFront
                    if showTorch {
                        Button { engine.setTorch(!engine.torchOn) } label: {
                            Image(systemName: "bolt.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }

                    // Flip camera button
                    Button { engine.switchCamera() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, topSafeInset() + 2)


                // Camera preview
                ZStack {
                    CameraPreviewView(engine: engine)

                    CrosshairCenter(color: Color(uiColor: engine.currentRGB.uiColor))
                        .frame(width: 22, height: 22)
                        .allowsHitTesting(false)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ColorIsland(
                            raw: engine.currentRGB,
                            color: engine.currentRGB,
                            catalog: catalog,
                            onCopy: {
                                let c = engine.currentRGB
                                UIPasteboard.general.string = "HEX: \(c.hex)\nRGB: \(c.rgbText)\nCMYK: \(c.cmykText)"
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.22)) { copiedPulse = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                                    withAnimation(.easeOut(duration: 0.18)) { copiedPulse = false }
                                }
                                toastMessage = "Copied to clipboard"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    toastMessage = nil
                                }
                            },
                            onFavorite: {
                                favs.add(color: engine.currentRGB)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { likedPulse = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                                    withAnimation(.easeOut(duration: 0.28)) { likedPulse = false }
                                }
                                toastMessage = "Added to Collections"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    toastMessage = nil
                                }
                            }
                        )
                        .environment(\.copyPulse, copiedPulse)
                        .environment(\.likePulse, likedPulse)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.black, lineWidth: 12))
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer(minLength: 8)

                // Bottom bar (only shutter + flip)
                // Bottom bar (only shutter centered)
                ZStack {
                    Rectangle().fill(Color.black).ignoresSafeArea(edges: .bottom)

                    // Shutter button perfectly centered
                    Button {
                        generatePaletteFromLive()
                        withAnimation(.easeOut(duration: 0.06)) { flash = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            withAnimation(.easeIn(duration: 0.12)) { flash = false }
                        }
                    } label: {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 62, height: 62)
                            Circle().fill(.white).frame(width: 50, height: 50)
                        }
                        .accessibilityLabel("Generate Palette")
                    }
                    .buttonStyle(SquishButtonStyle())
                }
                .padding(.top, 14)
                .padding(.bottom, bottomSafeInset() + 8)
                .frame(height: 110)
            }
        }
        // Toasts
        .overlay(alignment: .bottom) {
            if let message = toastMessage {
                ToastView(message: message)
                    .padding(.bottom, bottomSafeInset() + 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .sheet(item: $matches) { payload in
            MatchesView(payload: payload)
                .environmentObject(favs)
        }
    }

    // MARK: helpers

    private func topSafeInset() -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let win = scene.windows.first else { return 0 }
        return win.safeAreaInsets.top
    }

    private func bottomSafeInset() -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let win = scene.windows.first else { return 0 }
        return win.safeAreaInsets.bottom
    }

    private func generatePaletteFromLive() {
        guard let img = engine.lastFrame else { return }
        let gen = UIImpactFeedbackGenerator(style: .light); gen.impactOccurred()
        let colors = KMeans.palette(from: img, k: 10)
        matches = MatchesPayload(colors: colors, sourceImage: img)
        toastMessage = "Palette generated from live camera"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            toastMessage = nil
        }
    }
}

// MARK: - Crosshair + Button styles

struct CrosshairCenter: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().stroke(.white, lineWidth: 2)
            Rectangle().fill(.white).frame(width: 2, height: 8)
            Rectangle().fill(.white).frame(width: 8, height: 2)
        }
    }
}

struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}


// MARK: - Matches Payload
struct MatchesPayload: Identifiable, Equatable {
    let id = UUID()
    let colors: [RGB]
    let sourceImage: UIImage?
}

// MARK: - Environment Pulses

private struct CopyPulseKey: EnvironmentKey { static let defaultValue: Bool = false }
private struct LikePulseKey: EnvironmentKey { static let defaultValue: Bool = false }

extension EnvironmentValues {
    var copyPulse: Bool { get { self[CopyPulseKey.self] } set { self[CopyPulseKey.self] = newValue } }
    var likePulse: Bool { get { self[LikePulseKey.self] } set { self[LikePulseKey.self] = newValue } }
}

// MARK: - Color Island (bottom info panel)

struct ColorIsland: View {
    let raw: RGB
    let color: RGB
    let catalog: Catalog
    var onCopy: () -> Void
    var onFavorite: () -> Void

    @Environment(\.copyPulse) private var copyPulse
    @Environment(\.likePulse) private var likePulse

    private var precisionText: String {
        let d = raw.distance(to: color)
        let p = max(0, 1 - d/441.7) * 100
        return "Precision \(Int(round(p)))%"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(uiColor: color.uiColor))
                    .frame(width: 42, height: 42)
                    .overlay(Circle().stroke(.white.opacity(0.95), lineWidth: 2))

                VStack(alignment: .leading, spacing: 2) {
                    Text(catalog.nearestName(to: color)?.name ?? color.hex)
                        .font(.headline)
                        .lineLimit(1)
                    Text(precisionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button(action: onCopy) {
                        ZStack {
                            Image(systemName: "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                                .scaleEffect(copyPulse ? 1.18 : 1.0)
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .opacity(copyPulse ? 1 : 0)
                                .offset(y: -10)
                                .scaleEffect(copyPulse ? 1.0 : 0.5)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button(action: onFavorite) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                            .scaleEffect(likePulse ? 1.15 : 1.0)
                    }
                    .buttonStyle(.bordered)

                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Matches View

struct MatchesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore

    let payload: MatchesPayload

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Swatch strip
                    SwatchStrip(colors: payload.colors)
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1))
                        .padding(.horizontal)

                    VStack(spacing: 10) {
                        ForEach(Array(payload.colors.enumerated()), id: \.offset) { (idx, c) in
                            ColorBreakdownRow(index: idx+1, color: c)
                                .padding(.horizontal)
                        }
                    }

                    HStack {
                        Button {
                            favs.addPalette(name: nil, colors: payload.colors)
                        } label: {
                            Label("Save Palette", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top, 12)
            }
            .navigationTitle("Colour Matches")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

struct ColorBreakdownRow: View {
    let index: Int
    let color: RGB
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: color.uiColor))
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("#\(index)").font(.caption).foregroundStyle(.secondary)
                Text("HEX: \(color.hex)").font(.subheadline)
                Text("RGB: \(color.rgbText)").font(.footnote).foregroundStyle(.secondary)
                Text("CMYK: \(color.cmykText)").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct SwatchStrip: View {
    let colors: [RGB]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(max(colors.count, 1))
            HStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.offset) { (_, c) in
                    Rectangle()
                        .fill(Color(uiColor: c.uiColor))
                        .frame(width: w)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
