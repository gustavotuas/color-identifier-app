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
    private let frameInterval: CFTimeInterval = 0.25

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
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.lastFrame = nil   // 👈 Evita mostrar frame congelado
            }
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

        // 🔹 Detenemos el envío de frames temporalmente
        videoOut.setSampleBufferDelegate(nil, queue: nil)

        session.beginConfiguration()
        session.removeInput(current)

        let newPos: AVCaptureDevice.Position = (current.device.position == .back) ? .front : .back

        guard let newDev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPos),
            let newInput = try? AVCaptureDeviceInput(device: newDev),
            session.canAddInput(newInput) else {
            session.addInput(current)
            session.commitConfiguration()
            // 🔹 Restauramos el delegate
            videoOut.setSampleBufferDelegate(self, queue: queue)
            return
        }

        session.addInput(newInput)
        videoInput = newInput
        isUsingFront = (newPos == .front)
        session.commitConfiguration()

        // 🔹 Una vez configurada la cámara nueva, reactivamos el delegate
        videoOut.setSampleBufferDelegate(self, queue: queue)
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
            DispatchQueue.main.async {
                self.currentRGB = RGB(r: r, g: g, b: b)
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= frameInterval else { return }
        lastFrameTime = now
        let ciImage = CIImage(cvImageBuffer: pb)
        if let cg = ci.createCGImage(ciImage, from: ciImage.extent) {
            let img = UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .right)
            DispatchQueue.main.async {
                self.lastFrame = img
            }
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

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.focusTap(_:)))
        v.addGestureRecognizer(tap)

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

        @objc func focusTap(_ gesture: UITapGestureRecognizer) {
        guard let device = engine.activeDevice(),
            device.isFocusPointOfInterestSupported else { return }

        let view = gesture.view!
        let location = gesture.location(in: view)
        let normalizedPoint = CGPoint(x: location.x / view.bounds.size.width,
                                    y: location.y / view.bounds.size.height)

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = normalizedPoint
                device.focusMode = .autoFocus
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = normalizedPoint
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
        } catch {
            print("Focus error: \(error.localizedDescription)")
        }
    }

    }
}

// MARK: - Camera Screen

// MARK: - Camera Screen
// MARK: - Helpers globales

/// Normaliza un valor HEX: quita espacios, "#" y lo pasa a mayúsculas
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}


struct CameraScreen: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @EnvironmentObject var store: StoreVM
    @StateObject private var engine = CameraEngine()

    @State private var likedPulse = false
    @State private var copiedPulse = false
    @State private var flash = false
    @State private var toastMessage: String? = nil
    @State private var matches: MatchesPayload? = nil
    @State private var selection: CatalogSelection = VendorSelectionStorage.load() ?? .all
    @State private var showVendorSheet = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .animation(.easeInOut, value: UITraitCollection.current.userInterfaceStyle)

                VStack(spacing: 0) {
                    vendorFilterBanner
                    cameraPreviewSection
                    bottomBar
                }
            }
            .toolbar { toolbarItems }
            .onChange(of: selection, perform: handleSelectionChange)
            .overlay(alignment: .bottom) { toastOverlay }
            .onAppear(perform: handleAppear)
            .onDisappear { engine.stop() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in engine.stop() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in engine.start() }
            .sheet(item: $matches) { payload in
                MatchesView(payload: payload)
                    .environmentObject(favs)
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showVendorSheet) { vendorSheet }
    }

    // MARK: - Subviews

    private var vendorFilterBanner: some View {
        Group {
            if selection.isFiltered {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selection.filterSubtitle).lineLimit(1)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            selection = .all
                            VendorSelectionStorage.save(selection)
                            toastMessage = "Vendor filter cleared"
                        }
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .font(.caption.bold())
                }
                .font(.footnote)
                .padding(10)
                .background(Color.blue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.5)))
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var cameraPreviewSection: some View {
        ZStack {
            CameraPreviewView(engine: engine)
                .ignoresSafeArea(edges: .horizontal)

            CrosshairCenter(color: Color(uiColor: engine.currentRGB.uiColor))
                .frame(width: 22, height: 22)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ColorIsland(
                    raw: engine.currentRGB,
                    color: engine.currentRGB,
                    catalog: catalog,
                    selection: selection,        // 👈 nuevo
                    catalogs: catalogs,          // 👈 nuevo
                    onCopy: {},
                    onFavorite: handleFavorite
                )
                .environment(\.copyPulse, copiedPulse)
                .environment(\.likePulse, likedPulse)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .padding(.horizontal, 0) // 🔹 sin espacio lateral
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        ZStack {
            Rectangle()
                .fill(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)

            Button {
                generatePaletteFromLive()
                withAnimation(.easeOut(duration: 0.06)) { flash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeIn(duration: 0.12)) { flash = false }
                }
            } label: {
                ZStack {
                    Circle().stroke(Color.primary, lineWidth: 4).frame(width: 62, height: 62)
                    Circle().fill(Color.primary).opacity(0.2).frame(width: 50, height: 50)
                }
                .accessibilityLabel("Generate Palette")
            }
            .buttonStyle(SquishButtonStyle())
        }
        .padding(.top, 14)
        .padding(.bottom, bottomSafeInset() + 8)
        .frame(height: 110)
    }

    private var toastOverlay: some View {
        Group {
            if let message = toastMessage {
                ToastView(message: message)
                    .padding(.bottom, bottomSafeInset() + 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var vendorSheet: some View {
        VendorListSheet(
            selection: $selection,
            candidates: CatalogID.allCases.filter { $0 != .generic },
            catalogs: catalogs
        )
        .presentationDetents([.medium, .large])
        .onDisappear {
            withAnimation {
                if selection == .all {
                    toastMessage = "Vendor filter cleared"
                } else {
                    toastMessage = "Vendor filter set: \(selection.filterSubtitle)"
                }
            }
            VendorSelectionStorage.save(selection)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { toastMessage = nil }
        }
    }

    // MARK: - Toolbar (colócalo dentro de CameraScreen)
private var toolbarItems: some ToolbarContent {
    Group {
        // Leading
        ToolbarItem(placement: .navigationBarLeading) {
            Button { showVendorSheet = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Select vendor")
        }

        // Trailing
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Luz/Ambiente
            Image(systemName: (engine.brightness > 0.45) ? "sun.max.fill" : "cloud.fill")
                .foregroundStyle((engine.brightness > 0.45) ? .yellow : .orange)

            // Linterna (si disponible y no es cámara frontal)
            if (engine.activeDevice()?.hasTorch ?? false) && !engine.isUsingFront {
                Button { engine.setTorch(!engine.torchOn) } label: {
                    Image(systemName: "bolt.fill")
                }
            }

            // Cambiar cámara
            Button { engine.switchCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
            }

            // Paywall PRO
            if !store.isPro {
                Button { store.showPaywall = true } label: {
                    Text("PRO")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(colors: [.purple, .pink],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                }
            }
        }
    }
}


    // MARK: - Helpers

    private func handleFavorite() {
        let rgb = engine.currentRGB
        let key = normalizeHex(rgb.hex)

        // Armar pool de colores según el filtro activo (igual que SearchScreen)
        let pool: [NamedColor]
        switch selection {
        case .all:
            pool = catalog.names + catalogs.colors(for: Set(CatalogID.allCases.filter { $0 != .generic }))
        case .vendor(let id):
            pool = catalogs.colors(for: [id])
        case .genericOnly:
            pool = catalogs.colors(for: [.generic])
        }


        // Buscar el más cercano usando la misma comparación del PhotosScreen
        let nearest = pool.min(by: {
            hexToRGB($0.hex).distance(to: rgb) < hexToRGB($1.hex).distance(to: rgb)
        })

        // Calcular precisión
        var precision: Double = 100
        if let nearest = nearest {
            let diff = rgb.distance(to: hexToRGB(nearest.hex))
            let maxDiff = sqrt(3 * pow(255.0, 2.0))
            precision = max(0, 1 - diff / maxDiff) * 100
        }

        // Guardar / eliminar favorito
        if favs.colors.contains(where: { normalizeHex($0.color.hex) == key }) {
            favs.colors.removeAll { normalizeHex($0.color.hex) == key }
            toastMessage = "Removed from collections"
        } else {
            if let nearest = nearest {
                // 🔹 Quitamos el parámetro 'name:' para ajustarlo al método actual
                favs.add(color: rgb)
                toastMessage = "\(nearest.name) (\(Int(precision))%) added to collections"
            } else {
                favs.add(color: rgb)
                toastMessage = "Added to collections"
            }
        }

        // Animación visual igual
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { likedPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeOut(duration: 0.28)) { likedPulse = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            toastMessage = nil
        }
    }





    private func handleAppear() {
        selection = VendorSelectionStorage.load() ?? .all
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            engine.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { engine.start() }
        }
    }

    private func handleSelectionChange(_ newValue: CatalogSelection) {
        withAnimation {
            if newValue == .all {
                toastMessage = "Vendor filter cleared"
            } else {
                toastMessage = "Vendor filter set: \(newValue.filterSubtitle)"
            }
        }
        VendorSelectionStorage.save(newValue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            toastMessage = nil
        }
    }

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

    // MARK: - Matches View

    struct MatchesView: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var favs: FavoritesStore

        let payload: MatchesPayload

        var body: some View {
            NavigationView {
                ScrollView {
                    VStack(spacing: 16) {
                        SwatchStrip(colors: payload.colors)
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1))
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

    // MARK: - Supporting Views

    struct ColorBreakdownRow: View {
        let index: Int
        let color: RGB
        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(uiColor: color.uiColor))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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
}


struct CrosshairCenter: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 2)
            Rectangle().fill(Color.white).frame(width: 2, height: 8)
            Rectangle().fill(Color.white).frame(width: 8, height: 2)
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

// MARK: - Matches Payload + Environment keys

struct MatchesPayload: Identifiable, Equatable {
    let id = UUID()
    let colors: [RGB]
    let sourceImage: UIImage?
}

private struct CopyPulseKey: EnvironmentKey { static let defaultValue: Bool = false }
private struct LikePulseKey: EnvironmentKey { static let defaultValue: Bool = false }

extension EnvironmentValues {
    var copyPulse: Bool { get { self[CopyPulseKey.self] } set { self[CopyPulseKey.self] = newValue } }
    var likePulse: Bool { get { self[LikePulseKey.self] } set { self[LikePulseKey.self] = newValue } }
}

// MARK: - Color Island (minimal)

struct ColorIsland: View {
    let raw: RGB
    let color: RGB
    let catalog: Catalog
    let selection: CatalogSelection
    let catalogs: CatalogStore
    var onCopy: () -> Void
    var onFavorite: () -> Void

    @Environment(\.likePulse) private var likePulse

    // Arma el pool de colores según el filtro activo
    private var filteredPool: [NamedColor] {
        switch selection {
        case .all:
            return catalog.names + catalogs.colors(for: Set(CatalogID.allCases.filter { $0 != .generic }))
        case .vendor(let id):
            return catalogs.colors(for: [id]) // ✅ sólo colores del proveedor
        case .genericOnly:
            return catalogs.colors(for: [.generic])
        }
    }

    // Busca el color más cercano dentro del pool filtrado
    private var nearest: NamedColor? {
        guard !filteredPool.isEmpty else { return nil }
        return filteredPool.min(by: {
            hexToRGB($0.hex).distance(to: color) < hexToRGB($1.hex).distance(to: color)
        })
    }

    // Calcula precisión con base al color más cercano
    private var precisionValue: Double {
        guard let nearest = nearest else { return 0 }
        let diff = color.distance(to: hexToRGB(nearest.hex))
        let maxDiff = sqrt(3 * pow(255.0, 2.0))
        return max(0, 1 - diff / maxDiff) * 100
    }

    private var precisionColor: Color {
        switch precisionValue {
        case 80...100: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Preview del color actual detectado
                Circle()
                    .fill(Color(uiColor: color.uiColor))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(nearest?.name ?? color.hex)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(String(format: "Precision %.0f%%", precisionValue))
                        .font(.caption.bold())
                        .foregroundStyle(precisionColor)
                }

                Spacer()

                Button(action: onFavorite) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .symbolEffect(.bounce, value: likePulse)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .id(selection.filterSubtitle) // 🔥 fuerza a SwiftUI a refrescar al cambiar vendor
    }
}
