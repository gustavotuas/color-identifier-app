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
    private let frameInterval: CFTimeInterval = 0.5

    // 🔹 Filtro de suavizado de color
    private var recentColors: [RGB] = []
    private let maxSamples = 5


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
            let x = w / 2, y = h / 2
            let px = base.advanced(by: y * bpr + x * 4)
            let b = Int(px.load(fromByteOffset: 0, as: UInt8.self))
            let g = Int(px.load(fromByteOffset: 1, as: UInt8.self))
            let r = Int(px.load(fromByteOffset: 2, as: UInt8.self))
            let newColor = RGB(r: r, g: g, b: b)

            // 🔹 1. Calcular diferencia con el color actual
            let diff = currentRGB.distance(to: newColor)

            // 🔹 2. Solo actualizar si el cambio es relevante (> 20 en promedio RGB)
            if diff > 20 {
                // 🔹 3. Suavizado: promedio de últimos 5 colores
                addToRecentColors(newColor)

                let avgR = recentColors.map(\.r).reduce(0, +) / recentColors.count
                let avgG = recentColors.map(\.g).reduce(0, +) / recentColors.count
                let avgB = recentColors.map(\.b).reduce(0, +) / recentColors.count
                let averaged = RGB(r: avgR, g: avgG, b: avgB)

                DispatchQueue.main.async {
                    self.currentRGB = averaged
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        // 🔹 4. Captura periódica del frame (sin tocar el suavizado)
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

    // MARK: - Suavizado (promedio de últimos colores)
    private func addToRecentColors(_ color: RGB) {
        if recentColors.count >= maxSamples {
            recentColors.removeFirst()
        }
        recentColors.append(color)
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
    @State private var selection: CatalogSelection = VendorSelectionStorage.load() ?? .genericOnly
    @State private var showVendorSheet = false
    @State private var trialProgress: CGFloat = 0
    @State private var trialTimerActive = false
    @State private var showOverlay = false
    @State private var trialUsed = false




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
                LivePaletteDetailView(payload: payload)
                    .environmentObject(favs)
                    .environmentObject(catalog)
                    .environmentObject(catalogs)
                    .environmentObject(store)
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
                    Image(systemName: "paintpalette.fill")
                    Text(selection.filterSubtitle).lineLimit(1)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            selection = .genericOnly
                            VendorSelectionStorage.save(selection)
                            toastMessage = "Paint filter cleared"
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

        // ☀️ Luz / exposición
        // HStack {
        //     Image(systemName: engine.brightness > 0.45 ? "sun.max.fill" : "cloud.fill")
        //         .font(.system(size: 22, weight: .semibold))
        //         .foregroundStyle(engine.brightness > 0.45 ? .yellow : .gray)
        //         .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        //         .padding(.leading, 12)
        //         .padding(.top, 12)
        //         .transition(.opacity.combined(with: .scale))
        //         .animation(.easeInOut(duration: 0.25), value: engine.brightness > 0.45)
        //     Spacer()
        // }
        // .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // .ignoresSafeArea(edges: .top)

        // 🎯 Crosshair central
        CrosshairCenter(color: Color(uiColor: engine.currentRGB.uiColor))
            .frame(width: 22, height: 22)
            .allowsHitTesting(false)

        // 🎨 Island inferior (solo visible si no está bloqueado)
        if store.isPro || trialTimerActive {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ColorIsland(
                    raw: engine.currentRGB,
                    color: engine.currentRGB,
                    catalog: catalog,
                    selection: selection,
                    catalogs: catalogs,
                    onCopy: {},
                    onFavorite: handleFavorite
                )
                .environment(\.copyPulse, copiedPulse)
                .environment(\.likePulse, likedPulse)
                .environmentObject(store)
            }
        }


        // 🧩 Overlay para usuarios no Pro
        // 🧩 Overlay de preview (barra de tiempo)
        // 🧩 Overlay de preview (barra de tiempo + texto)
        if !store.isPro && trialTimerActive {
            VStack(spacing: 6) {
                // 🔹 Texto informativo
                Text("Free Preview – Unlock PRO for full access")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .transition(.opacity)
                    .padding(.top, 6)

                // 🔵 Barra progresiva arriba (con borde blanco y gradiente vibrante)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 14)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "#3C8CE7"), // azul brillante
                                        Color(hex: "#6F3CE7"), // violeta intenso
                                        Color(hex: "#C63DE8"), // púrpura neón
                                        Color(hex: "#FF61B6")  // fucsia vibrante
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * trialProgress, height: 14)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.9), lineWidth: 1.2) // 🔹 Borde blanco
                            )
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    }
                }
                .frame(height: 14)
                .padding(.horizontal, 20)

                Spacer()
            }
            .transition(.opacity)
        }

                
        // 🧩 Overlay final (bloqueo completo)
        if !store.isPro && showOverlay {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 4)

                    Text("Unlock Full Live Camera")
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    Button {
                        store.showPaywall = true
                    } label: {
                        Text("Go Pro")
                            .font(.headline)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(colors: [.purple, .pink],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing)
                            )
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(radius: 4)
                    }
                }
                .padding(20)
            }
            .transition(.opacity)
        }

    }
    .clipShape(RoundedRectangle(cornerRadius: 26))
    .padding(.horizontal, 12)
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
            catalogs: catalogs,
            isPro: store.isPro
        )
        .presentationDetents([.medium, .large])
        .onDisappear {
            withAnimation {
                    toastMessage = "Paint filter set: \(selection.filterSubtitle)"
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
                Image(systemName: "paintpalette.fill")
            }
            .accessibilityLabel("Select Paint")
        }

        // Trailing
        ToolbarItemGroup(placement: .navigationBarTrailing) {

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

    // 1️⃣ Construir pool de colores según el filtro activo
    let pool: [NamedColor]
    switch selection {
    case .vendor(let id):
        pool = catalogs.colors(for: [id])
    case .genericOnly:
        pool = catalogs.colors(for: [.generic])
    }

    // 2️⃣ Buscar el color más cercano en el catálogo filtrado
    guard let nearest = pool.min(by: {
        hexToRGB($0.hex).distance(to: rgb) < hexToRGB($1.hex).distance(to: rgb)
    }) else {
        toastMessage = "No match found"
        return
    }

    // 3️⃣ Calcular precisión
    let diff = rgb.distance(to: hexToRGB(nearest.hex))
    let maxDiff = sqrt(3 * pow(255.0, 2.0))
    let precision = max(0, 1 - diff / maxDiff) * 100

    // 4️⃣ Convertir el color coincidente a RGB para el FavoritesStore
    let matchedRGB = hexToRGB(nearest.hex)

    // 5️⃣ Guardar o eliminar
    if favs.colors.contains(where: { normalizeHex($0.color.hex) == normalizeHex(nearest.hex) }) {
        favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(nearest.hex) }
        toastMessage = "Removed from Collections"
    } else {
        favs.add(color: matchedRGB)
        toastMessage = "Added to Collections \(nearest.name) (\(Int(precision))%)"
    }

    // 6️⃣ Animación del corazón
    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
        likedPulse = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
        withAnimation(.easeOut(duration: 0.28)) { likedPulse = false }
    }

    // 7️⃣ Ocultar el toast
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
        toastMessage = nil
    }
}






    private func handleAppear() {
    selection = VendorSelectionStorage.load() ?? .genericOnly

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        engine.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            engine.start()

            // 🎬 Solo preview temporal si no es Pro y no lo ha usado en esta sesión
            if !store.isPro && !trialUsed {
                trialUsed = true // ✅ se marca solo durante esta sesión
                trialProgress = 0
                trialTimerActive = true
                let duration: Double = 8.0 // segundos de preview
                
                withAnimation(.linear(duration: duration)) {
                    trialProgress = 1.0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    trialTimerActive = false
                    showOverlay = true
                    // toastMessage = "Preview ended – Unlock full camera"
                    // DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    //     toastMessage = nil
                    //     store.showPaywall = true
                    // }
                }
            } else if !store.isPro && trialUsed {
                // 👇 si ya tuvo el trial en esta sesión, mostrar overlay directo
                showOverlay = true
            }
        }
    }
}



    private func handleSelectionChange(_ newValue: CatalogSelection) {
        withAnimation {
                toastMessage = "Paint filter set: \(newValue.filterSubtitle)"
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

        // Vibración ligera al capturar
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()

        // 🎨 Generar paleta con KMeans
        var colors = KMeans.palette(from: img, k: 10)

        // 🟡 Color actual del crosshair
        let current = engine.currentRGB

        // Si el color detectado no está en la lista, agrégalo
        if !colors.contains(where: { $0.hex.lowercased() == current.hex.lowercased() }) {
            colors.append(current)
        }

        // 🔹 Ordenar la paleta completa por luminancia (para mantener consistencia global)
        colors = sortPalette(colors)

        // Crear payload incluyendo la imagen fuente
        matches = MatchesPayload(colors: colors, sourceImage: img)

        // Mostrar toast
        // toastMessage = "Palette generated from live camera"
        // DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
        //     toastMessage = nil
        // }
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
    @EnvironmentObject var store: StoreVM


    // Arma el pool de colores según el filtro activo
    private var filteredPool: [NamedColor] {
        switch selection {
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
                // Nombre del color o hex si no tiene nombre
                Text(nearest?.name ?? color.hex)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Nueva línea: HEX + vendor brand/code si existen
                // if let nearest = nearest {
                //     HStack(spacing: 6) {
                //         Text(nearest.hex)
                //             .font(.caption)
                //             .foregroundColor(.white.opacity(0.8))
                //         if let brand = nearest.vendor?.brand, let code = nearest.vendor?.code {
                //             Text("• \(brand) \(code)")
                //                 .font(.caption)
                //                 .foregroundColor(.white.opacity(0.8))
                //                 .lineLimit(1)
                //         }
                //     }
                // } else {
                //     Text(color.hex)
                //         .font(.caption)
                //         .foregroundColor(.white.opacity(0.8))
                // }

                // Línea existente de precisión (queda igual)
                Text(String(format: "Precision %.0f%%", precisionValue))
                    .font(.caption.bold())
                    .foregroundStyle(precisionColor)
            }


                Spacer()

                // 🔒 Solo mostrar botón Save si el usuario es PRO
                if store.isPro {
                    Button(action: onFavorite) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: likePulse)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save color to collections")
                }
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
