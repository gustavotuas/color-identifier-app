import SwiftUI

struct ColorWheelView: View {
    let colors: [NamedColor]
    @Namespace private var animation
    @EnvironmentObject var favs: FavoritesStore

    @State private var selectedColor: NamedColor? = nil
    @State private var showDetail = false
    @State private var generatedPalette: [RGB] = []

    var body: some View {
        VStack(spacing: 24) {
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2.3
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                ZStack {
                    // Base ring
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 2)
                        .frame(width: radius * 2, height: radius * 2)

                    // Harmony lines when selected
                    if let selected = selectedColor {
                        let rgb = hexToRGB(selected.hex)
                        let hue = rgbToHue(rgb)
                        let harmonyAngles = harmonyAngles(for: hue)

                        ForEach(harmonyAngles, id: \.self) { angle in
                            let x = center.x + CGFloat(cos(angle.radians)) * radius
                            let y = center.y + CGFloat(sin(angle.radians)) * radius

                            Path { path in
                                path.move(to: center)
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                            .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                        }
                    }

                    // Organized color wheel (Hue–Saturation mapping)
                    ForEach(Array(colors.prefix(100).enumerated()), id: \.offset) { i, color in
                        let rgb = hexToRGB(color.hex)
                        let (h, s, _) = rgbToHSL(rgb)
                        
                        let angle = Angle(degrees: h)
                        let normalizedSat = max(0.15, s) // evita que los 0 se junten al centro
                        let radius = min(geo.size.width, geo.size.height) / 2.3 * normalizedSat

                        let x = center.x + CGFloat(cos(angle.radians)) * radius
                        let y = center.y + CGFloat(sin(angle.radians)) * radius

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



                    // Highlight center info
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
            }
            .padding()

            // 🎨 Generated Palette Section
            if !generatedPalette.isEmpty {
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
                            Text("Save Palette to Favorites")
                                .fontWeight(.semibold)
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

    // MARK: - Helpers

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
        return hues.map {
            hueShift(rgb: base, degrees: Double($0))
        }
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
