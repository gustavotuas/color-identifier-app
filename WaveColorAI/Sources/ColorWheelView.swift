import SwiftUI

struct ColorWheelView: View {
    let colors: [NamedColor]
    @Namespace private var animation
    @EnvironmentObject var favs: FavoritesStore

    // Selección y detalle
    @State private var selectedColor: NamedColor? = nil
    @State private var showDetail = false
    @State private var generatedPalette: [RGB] = []

    // Interacción: zoom, pan, rotación
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero

    // Doble-tap anchoring
    @State private var wheelSize: CGSize = .zero

    // Límite de puntos para rendimiento
    private let maxDots = 240

    var body: some View {
        VStack(spacing: 20) {

            // Contenedor con gestos compuestos
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let baseRadius = side / 2.3
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                ZStack {
                    // Base ring
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 2)
                        .frame(width: baseRadius * 2, height: baseRadius * 2)

                    // Líneas de armonía (rotan junto con la rueda)
                    if let selected = selectedColor {
                        let rgbSel = hexToRGB(selected.hex)
                        let hueSel = rgbToHue(rgbSel)
                        let harmonyAngles = harmonyAngles(for: hueSel).map { $0 + rotation }

                        ForEach(harmonyAngles, id: \.self) { angle in
                            let x = center.x + CGFloat(cos(angle.radians)) * baseRadius
                            let y = center.y + CGFloat(sin(angle.radians)) * baseRadius

                            Path { path in
                                path.move(to: center)
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                            .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                        }
                    }

                    // Puntos organizados por Hue/Sat (rotados)
                    let sample = Array(colors.prefix(maxDots)).enumerated().map { $0 }
                    ForEach(sample, id: \.offset) { i, color in
                        let rgb = hexToRGB(color.hex)
                        let (h, s, _) = rgbToHSL(rgb)

                        // aplica rotación global
                        let angle = Angle(degrees: h) + rotation
                        let normalizedSat = max(0.15, s)
                        let r = baseRadius * normalizedSat

                        let x = center.x + CGFloat(cos(angle.radians)) * r
                        let y = center.y + CGFloat(sin(angle.radians)) * r

                        Circle()
                            .fill(Color(rgb.uiColor))
                            .frame(width: selectedColor?.id == color.id ? 52 : 26,
                                   height: selectedColor?.id == color.id ? 52 : 26)
                            .shadow(color: .black.opacity(0.25), radius: 3)
                            .position(x: x, y: y)
                            .matchedGeometryEffect(id: color.id, in: animation)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                    if selectedColor?.id == color.id {
                                        showDetail = true
                                    } else {
                                        selectedColor = color
                                        generatedPalette = generatePalette(from: rgb)
                                    }
                                }
                            }
                    }

                    // Centro con preview del seleccionado
                    if let selected = selectedColor {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(hexToRGB(selected.hex).uiColor))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                                )
                                .shadow(radius: 6)
                                .matchedGeometryEffect(id: selected.id, in: animation)

                            Text(selected.name)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(selected.hex)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 8)
                        .position(center)
                        .transition(.scale.combined(with: .opacity))
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.easeInOut) {
                                selectedColor = nil
                                generatedPalette = []
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(
                    GeometryReader { inner in
                        Color.clear.onAppear {
                            wheelSize = inner.size
                        }
                    }
                )
                // Gestos (rotación + pinch + pan)
                .gesture(
                    simultaneousGestures()
                )
                // Transformaciones (primero rotación -> luego zoom -> luego pan para sensación natural)
                .rotationEffect(rotation)
                .scaleEffect(scale, anchor: .center)
                .offset(offset)
                // Doble tap: toggle zoom 1x/2x tratando de centrar hacia el toque
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        toggleDoubleTapZoom()
                    }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
            .padding(.horizontal)
            .frame(height: 360)

            // Controles flotantes
            controlBar

            // 🎨 Paleta generada
            if !generatedPalette.isEmpty {
                paletteSection
            }
        }
        .sheet(isPresented: $showDetail) {
            if let selected = selectedColor {
                ColorDetailView(color: selected)
                    .onDisappear {
                        withAnimation(.spring()) {
                            selectedColor = nil
                            generatedPalette = []
                        }
                    }
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring()) { resetTransforms() }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)

            Button {
                withAnimation(.spring()) { nudgeScale(by: -0.2) }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)

            Button {
                withAnimation(.spring()) { nudgeScale(by: 0.2) }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)

            Spacer()

            // Indicadores compactos
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right")
                    Text("\(Int(scale * 100))%")
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())

                HStack(spacing: 4) {
                    Image(systemName: "goforward")
                    Text("\(Int((rotation.degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)))°")
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Palette Section

    private var paletteSection: some View {
        VStack(spacing: 16) {
            Text("Generated Palette")
                .font(.headline)
                .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(generatedPalette, id: \.hex) { rgb in
                        VStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(rgb.uiColor))
                                .frame(width: 60, height: 60)
                                .shadow(radius: 2)
                            Text(rgb.hex)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Button(action: savePalette) {
                HStack {
                    Image(systemName: "heart.fill")
                    Text("Save Palette to Favorites").fontWeight(.semibold)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(LinearGradient(colors: [.purple, .pink],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing))
                .foregroundColor(.white)
                .cornerRadius(10)
                .shadow(radius: 3)
            }
            .padding(.bottom, 10)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: generatedPalette)
    }

    // MARK: - Gestures

    private func simultaneousGestures() -> some Gesture {
        // Magnify
        let magnify = MagnificationGesture()
            .onChanged { value in
                let newScale = (lastScale * value).clamped(to: 1.0...3.0)
                scale = newScale
            }
            .onEnded { _ in
                lastScale = scale
            }

        // Rotate
        let rotate = RotationGesture()
            .onChanged { value in
                rotation = lastRotation + value
            }
            .onEnded { _ in
                lastRotation = rotation
            }

        // Pan (solo si hay zoom > 1)
        let pan = DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard scale > 1.02 else { offset = .zero; return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                // un pequeño clamp para que no se vaya “demasiado” lejos
                let maxOffset: CGFloat = 400
                offset = CGSize(width: offset.width.clamped(to: -maxOffset...maxOffset),
                                height: offset.height.clamped(to: -maxOffset...maxOffset))
                lastOffset = offset
            }

        // Combínalos simultáneamente
        return SimultaneousGesture(SimultaneousGesture(magnify, rotate), pan)
    }

    private func toggleDoubleTapZoom() {
        if scale < 1.5 {
            scale = 2.0
            lastScale = scale
        } else {
            scale = 1.0
            lastScale = scale
            offset = .zero
            lastOffset = .zero
        }
    }

    private func nudgeScale(by delta: CGFloat) {
        let new = (scale + delta).clamped(to: 1.0...3.0)
        scale = new
        lastScale = new
        if new <= 1.02 {
            withAnimation(.easeInOut) {
                offset = .zero
                lastOffset = .zero
            }
        }
    }

    private func resetTransforms() {
        scale = 1.0
        lastScale = 1.0
        rotation = .zero
        lastRotation = .zero
        offset = .zero
        lastOffset = .zero
    }

    // MARK: - Color Math

    private func rgbToHue(_ rgb: RGB) -> Double {
        let r = Double(rgb.r) / 255
        let g = Double(rgb.g) / 255
        let b = Double(rgb.b) / 255

        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal

        var hue: Double = 0
        if delta != 0 {
            if maxVal == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxVal == g {
                hue = ((b - r) / delta) + 2
            } else {
                hue = ((r - g) / delta) + 4
            }
            hue *= 60
        }
        if hue < 0 { hue += 360 }
        return hue
    }

    private func harmonyAngles(for hue: Double) -> [Angle] {
        [
            Angle(degrees: hue),
            Angle(degrees: (hue + 180).truncatingRemainder(dividingBy: 360)), // Complementary
            Angle(degrees: (hue + 30).truncatingRemainder(dividingBy: 360)),  // Analogous +
            Angle(degrees: (hue - 30).truncatingRemainder(dividingBy: 360)),  // Analogous -
            Angle(degrees: (hue + 120).truncatingRemainder(dividingBy: 360)), // Triadic 1
            Angle(degrees: (hue - 120).truncatingRemainder(dividingBy: 360))  // Triadic 2
        ]
    }

    // 🎨 Generate related palette
    private func generatePalette(from base: RGB) -> [RGB] {
        let hues = [0, 30, -30, 120, 180]
        return hues.map { hueShift(rgb: base, degrees: Double($0)) }
    }

    private func hueShift(rgb: RGB, degrees: Double) -> RGB {
        var h, s, l: Double
        (h, s, l) = rgbToHSL(rgb)
        h = (h + degrees).truncatingRemainder(dividingBy: 360)
        return hslToRGB(h, s, l)
    }

    private func rgbToHSL(_ rgb: RGB) -> (Double, Double, Double) {
        let r = Double(rgb.r) / 255
        let g = Double(rgb.g) / 255
        let b = Double(rgb.b) / 255

        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal

        var h = 0.0
        if delta != 0 {
            if maxVal == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxVal == g {
                h = ((b - r) / delta) + 2
            } else {
                h = ((r - g) / delta) + 4
            }
            h *= 60
        }
        if h < 0 { h += 360 }

        let l = (maxVal + minVal) / 2
        let s = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))
        return (h, s, l)
    }

    private func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> RGB {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2

        var r = 0.0, g = 0.0, b = 0.0
        switch h {
        case 0..<60: (r, g, b) = (c, x, 0)
        case 60..<120: (r, g, b) = (x, c, 0)
        case 120..<180: (r, g, b) = (0, c, x)
        case 180..<240: (r, g, b) = (0, x, c)
        case 240..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }

        return RGB(r: Int((r + m) * 255),
                   g: Int((g + m) * 255),
                   b: Int((b + m) * 255))
    }

    // 💾 Save to favorites
    private func savePalette() {
        guard !generatedPalette.isEmpty else { return }
        favs.add(palette: generatedPalette)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.easeInOut) {
            generatedPalette = []
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
