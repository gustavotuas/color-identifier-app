import SwiftUI
import UIKit

// MARK: - Local helpers
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

enum ColorInfoMode: String, CaseIterable { case rgb = "RGB", hex = "HEX", hsb = "HSB", cmyk = "CMYK" }
enum HarmonyMode: String, CaseIterable { case analogous = "Analogous", complementary = "Complementary", triadic = "Triadic"
//, monochromatic = "Monochromatic" 
}

// MARK: - Main
struct ColorDetailView: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let color: NamedColor

    @State private var selectedTab: ColorInfoMode = .rgb
    @State private var harmonyMode: HarmonyMode = .analogous
    @State private var toastMessage: String? = nil

    @State private var isFavorite = false
    @State private var likePulse = false

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    @State private var selectedHarmonyColor: NamedColor? = nil
    @State private var showHarmonySheet = false

    private var rgb: RGB { hexToRGB(color.hex) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {

                        // MARK: - Preview
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color(rgb.uiColor))
                            .frame(height: 220)
                            .overlay(
                                VStack(spacing: 4) {
                                    let textColor: Color = rgb.uiColor.isLight ? .black : .white
                                    Text(color.name)
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundColor(textColor)
                                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                                    Text(color.hex)
                                        .font(.subheadline)
                                        .foregroundColor(textColor.opacity(0.92))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                            )
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                            .padding(.horizontal)

                        // MARK: - Actions (Copy / Share / Add)
                        HStack(spacing: 30) {
                            // Copy
                            VStack(spacing: 6) {
                                Button(action: copyCurrentValue) {
                                    Image(systemName: "doc.on.doc").font(.title3)
                                }
                                Text("Copy").font(.caption2)
                            }

                            // Share
                            VStack(spacing: 6) {
                                Button(action: {
                                    withAnimation(.spring()) {
                                        shareCurrentValue()
                                    }
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title3)
                                }

                                Text("Share").font(.caption2)
                            }

                            // Add (+) → Added (check)
                            VStack(spacing: 6) {
                                Button(action: addOrRemoveFavorite) {
                                    Image(systemName: isFavorite ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.title3)
                                        .foregroundStyle(isFavorite ? .green : .primary)
                                        .scaleEffect(likePulse ? 1.12 : 1.0)
                                        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: likePulse)
                                }
                                Text(isFavorite ? "Added" : "Add").font(.caption2)
                            }
                        }
                        .foregroundColor(.primary)
                        .padding(.top, 2)

                        // MARK: - Color Info (container)
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Mode", selection: $selectedTab) {
                                ForEach(ColorInfoMode.allCases, id: \.self) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedTab) { _ in UIImpactFeedbackGenerator(style: .soft).impactOccurred() }

                            VStack(spacing: 10) {
                                switch selectedTab {
                                case .rgb:
                                    ValueRow(label: "Red",   value: "\(rgb.r)", color: .red,   onCopy: copyFromRow)
                                    ValueRow(label: "Green", value: "\(rgb.g)", color: .green, onCopy: copyFromRow)
                                    ValueRow(label: "Blue",  value: "\(rgb.b)", color: .blue,  onCopy: copyFromRow)
                                case .hex:
                                    ValueRow(label: "Hex", value: color.hex, color: .gray, onCopy: copyFromRow)
                                case .hsb:
                                    let (h, s, b) = rgbToHSB(rgb)
                                    ValueRow(label: "Hue",        value: "\(Int(h))°", color: .orange, onCopy: copyFromRow)
                                    ValueRow(label: "Saturation", value: "\(Int(s))%", color: .pink,   onCopy: copyFromRow)
                                    ValueRow(label: "Brightness", value: "\(Int(b))%", color: .yellow, onCopy: copyFromRow)
                                case .cmyk:
                                    let (c, m, y, k) = rgbToCMYK(rgb)
                                    ValueRow(label: "Cyan",    value: "\(Int(c))%", color: .cyan,   onCopy: copyFromRow)
                                    ValueRow(label: "Magenta", value: "\(Int(m))%", color: .pink,   onCopy: copyFromRow)
                                    ValueRow(label: "Yellow",  value: "\(Int(y))%", color: .yellow, onCopy: copyFromRow)
                                    ValueRow(label: "Black",   value: "\(Int(k))%", color: .black,  onCopy: copyFromRow)
                                }
                            }
                            .padding(12)
                            .background(scheme == .dark ? Color(.secondarySystemBackground) : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        }
                        .padding(.horizontal)


                        // MARK: - Harmony (container)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Color Harmony").font(.headline)
                                Spacer()
                            }

                            Picker("Harmony", selection: $harmonyMode) {
                                ForEach(HarmonyMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            HarmonyStrip(base: rgb, mode: harmonyMode) { tapped in
                                if store.isPro {
                                    if let found = findNamedColor(hex: tapped.hex) {
                                        selectedHarmonyColor = found
                                        showHarmonySheet = true
                                    } else {
                                        showToast("Color not found in library")
                                    }
                                } else {
                                    store.showPaywall = true
                                }
                            }
                        }
                        .padding(12)
                        .background(scheme == .dark ? Color(.secondarySystemBackground) : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        .padding(.horizontal)
                        .overlay {
                            if !store.isPro {
                                ProBlurOverlay()
                                    .padding(.horizontal, 0)
                            }
                        }



                        // MARK: - Shades & Tints Section
                        // MARK: - Shades & Tints Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Shades & Tints").font(.headline)
                                Spacer()
                            }

                            ShadesAndTintsView(base: rgb) { tapped in
                                if store.isPro {
                                    if let found = findNamedColor(hex: tapped.hex) {
                                        selectedHarmonyColor = found
                                        showHarmonySheet = true
                                    } else {
                                        showToast("Color not found in library")
                                    }
                                } else {
                                    store.showPaywall = true
                                }
                            }
                        }
                        .padding(12)
                        .background(scheme == .dark ? Color(.secondarySystemBackground) : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        .padding(.horizontal)
                        .overlay {
                            if !store.isPro {
                                ProBlurOverlay()
                                    .padding(.horizontal, 0)
                            }
                        }



                        // MARK: - Contrast Preview Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Contrast Preview").font(.headline)
                                Spacer()
                            }

                            ContrastPreviewView(color: rgb)
                        }
                        .padding(12)
                        .background(scheme == .dark ? Color(.secondarySystemBackground) : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        .padding(.horizontal)


                        // MARK: - Vendor Info (container)
                        if let v = color.vendor {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Vendor").font(.headline)
                                if let brand = v.brand, !brand.isEmpty { InfoRow(label: "Brand", value: brand) }
                                if let code = v.code, !code.isEmpty { InfoRow(label: "Code", value: code) }
                                if let locator = v.locator, !locator.isEmpty, locator.uppercased() != "N/A" {
                                    InfoRow(label: "Locator", value: locator)
                                    if let url = URL(string: locator), UIApplication.shared.canOpenURL(url) {
                                        Button("Open Vendor Page") { UIApplication.shared.open(url) }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.accentColor)
                                            .padding(.top, 6)
                                    }
                                }
                                if let line = v.line, !line.isEmpty { InfoRow(label: "Line", value: line) }
                            }
                            .padding(12)
                            .background(scheme == .dark ? Color(.secondarySystemBackground) : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                            .padding(.horizontal)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.bottom, 60)
                }

                // Toast inferior (usa tu ToastView a través del modifier .toast)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Close")
                        }
                        .font(.headline)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .toast(message: $toastMessage) // <- tu ToastView inferior

            // iOS share sheet
            .sheet(isPresented: $showShareSheet) {
                if !shareItems.isEmpty {
                    ActivityViewController(items: shareItems)
                }
            }
            // Harmony detail (sin requerir Identifiable)
            .sheet(isPresented: Binding(
                get: { showHarmonySheet && selectedHarmonyColor != nil },
                set: { if !$0 { showHarmonySheet = false; selectedHarmonyColor = nil } }
            )) {
                if let c = selectedHarmonyColor {
                    ColorDetailView(color: c)
                        .environmentObject(favs)
                        .environmentObject(store)
                        .environmentObject(catalog)
                        .environmentObject(catalogs)
                }
            }
        }
        .onAppear {
            isFavorite = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(color.hex) }
        }
    }

    // MARK: - Actions
    private func showToast(_ text: String) {
        withAnimation { toastMessage = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { toastMessage = nil }
        }
    }

    private func copyCurrentValue() {
        let text = currentValueString()
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showToast("Copied to clipboard")
    }

    private func shareCurrentValue() {
        let isProUser = store.isPro
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showToast("Preparing share preview...")

        Task.detached(priority: .userInitiated) {
            // 1️⃣ Generar imagen
            let image = await generateShareImage()
            let tempDir = FileManager.default.temporaryDirectory
            let safeName = color.name.replacingOccurrences(of: " ", with: "_")
            let fileURL = tempDir.appendingPathComponent("Colorit_\(safeName).png")

            if let data = image.pngData() {
                try? data.write(to: fileURL)
            }

            // 2️⃣ Preparar texto
            var message = """
            🎨 \(color.name)
            HEX: \(color.hex)
            RGB: \(rgb.r), \(rgb.g), \(rgb.b)
            """

            if isProUser {
                let (h, s, b) = rgbToHSB(rgb)
                let (c, m, y, k) = rgbToCMYK(rgb)
                message += """

                HSB: \(Int(h))°, \(Int(s))%, \(Int(b))%
                CMYK: \(Int(c))%, \(Int(m))%, \(Int(y))%, \(Int(k))%
                """

                if let v = color.vendor {
                    message += """

                    🏷️ Vendor: \(v.brand ?? "—")
                    Code: \(v.code ?? "—")
                    Line: \(v.line ?? "—")
                    """
                }
            } else {
                message += "\n\n📱 Made with Colorit – www.colorit.app"
            }

            // 3️⃣ Volver al main thread para mostrar el share sheet
            DispatchQueue.main.async {
                showToast("Opening share sheet...")

                let activityVC = UIActivityViewController(activityItems: [message, fileURL], applicationActivities: nil)
                activityVC.excludedActivityTypes = [.assignToContact, .addToReadingList]

                // ✅ Presentación compatible con SwiftUI
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let rootVC = scene.windows.first?.rootViewController {
                    var top = rootVC
                    while let presented = top.presentedViewController { top = presented }
                    top.present(activityVC, animated: true)
                } else {
                    print("⚠️ Could not find a valid rootViewController to present share sheet.")
                    showToast("Failed to open share sheet.")
                }
            }
        }
    }

    // MARK: - Pro Unlock Overlay (reutilizado de PhotosScreen)
    private struct ProBlurOverlay: View {
        @EnvironmentObject var store: StoreVM

        var body: some View {
            ZStack {
                // Capa base de blur con degradado vertical
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 10)
                    .opacity(0.95)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.0), location: 0.0),
                                .init(color: .white.opacity(1.0), location: 0.35),
                                .init(color: .white.opacity(1.0), location: 0.65),
                                .init(color: .white.opacity(1.0), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Botón mágico de desbloqueo
                MagicalUnlockButtonSmall(title: "Unlock Pro")
                    .onTapGesture { store.showPaywall = true }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .transition(.opacity)
        }
    }

    private struct MagicalUnlockButtonSmall: View {
        let title: String

        var body: some View {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.purple, Color.pink, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.pink.opacity(0.3), radius: 5, y: 2)
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .scaleEffect(1.02)
                .padding(.vertical, 4)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: title)
        }
    }




    private func addOrRemoveFavorite() {
        let rgbValue = hexToRGB(color.hex)
        let key = normalizeHex(rgbValue.hex)

        if favs.colors.contains(where: { normalizeHex($0.color.hex) == key }) {
            favs.colors.removeAll { normalizeHex($0.color.hex) == key }
            isFavorite = false
            showToast("Removed from Collections")
        } else {
            favs.add(color: rgbValue) // agrega a favoritos individuales
            isFavorite = true
            showToast("Added to Collections")
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) { likePulse.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { likePulse = false }
    }

    private func copyFromRow(_ text: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showToast("Copied \(text)")
    }

    // MARK: - Shades and Tints Helper
private func shadesAndTints(for rgb: RGB) -> [RGB] {
    let (h, s, b) = rgbToHSB(rgb)
    // Variaciones más oscuras y claras del color base
    let steps: [CGFloat] = [-40, -20, 0, 20, 40]
    return steps.map { delta in
        hsbToRGB(hue: h, s: s, b: max(0, min(100, b + delta)))
    }
}

@MainActor
private func generateShareImage() -> UIImage {
    let shareView = VStack(spacing: 18) {

        // MARK: - Color preview
        RoundedRectangle(cornerRadius: 22)
            .fill(Color(rgb.uiColor))
            .frame(height: 220)
            .overlay(
                VStack(spacing: 4) {
                    Text(color.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(rgb.uiColor.isLight ? .black : .white)
                    Text(color.hex)
                        .font(.subheadline)
                        .foregroundStyle(rgb.uiColor.isLight ? .black.opacity(0.85) : .white.opacity(0.85))
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            )
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

        // MARK: - Color Harmony
        if store.isPro {
            VStack(alignment: .leading, spacing: 12) {
                Text("Color Harmony").font(.headline)
                HarmonyStrip(base: rgb, mode: harmonyMode) { _ in }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        } else {
            VStack(alignment: .center, spacing: 14) {
                Text("Unlock Pro to view Harmony & Tints")
                    .font(.headline)
                    .foregroundColor(.secondary)
                MagicalUnlockButtonSmall(title: "Unlock Pro")
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(30)
            .background(Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }



        // MARK: - Shades & Tints
        if store.isPro {
            VStack(alignment: .leading, spacing: 12) {
                Text("Shades & Tints").font(.headline)
                ShadesAndTintsView(base: rgb) { _ in }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        } else {
            VStack(alignment: .center, spacing: 14) {
                Text("Unlock Pro to view Shades & Tints")
                    .font(.headline)
                    .foregroundColor(.secondary)
                MagicalUnlockButtonSmall(title: "Unlock Pro")
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(30)
            .background(Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }

        // MARK: - Contrast Preview
        VStack(alignment: .leading, spacing: 12) {
            Text("Contrast Preview").font(.headline)
            ContrastPreviewView(color: rgb)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

        // MARK: - Footer
        Text("Made with Colorit.app")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 8)
    }
    .padding(.horizontal, 20)   // 👈 margen lateral sutil
    .padding(.vertical, 30)
    .background(Color(.systemGroupedBackground))

    let renderer = ImageRenderer(content: shareView)
    renderer.scale = UIScreen.main.scale
    return renderer.uiImage ?? UIImage()
}



    private func currentValueString() -> String {
        switch selectedTab {
        case .rgb: return "RGB: \(rgb.r), \(rgb.g), \(rgb.b)"
        case .hex: return "HEX: \(color.hex)"
        case .hsb:
            let (h, s, b) = rgbToHSB(rgb)
            return "HSB: \(Int(h))°, \(Int(s))%, \(Int(b))%"
        case .cmyk:
            let (c, m, y, k) = rgbToCMYK(rgb)
            return "CMYK: \(Int(c))%, \(Int(m))%, \(Int(y))%, \(Int(k))%"
        }
    }

    // MARK: - Catalog matching
    private func findNamedColor(hex: String) -> NamedColor? {
        let target = normalizeHex(hex)
        // 1) genéricos
        if let exact = catalog.names.first(where: { normalizeHex($0.hex) == target }) {
            return exact
        }
        // 2) vendors
        let vendorIDs = Set(CatalogID.allCases.filter { $0 != .generic })
        let vendorColors = catalogs.colors(for: vendorIDs)
        if let match = vendorColors.first(where: { normalizeHex($0.hex) == target }) {
            return match
        }
        // 3) fallback: el más cercano (si quieres)
        let pool = (catalogs.loaded[.generic] ?? catalog.names) + vendorColors
        return pool.min { a, b in
            hexToRGB(a.hex).distance(to: hexToRGB(hex)) < hexToRGB(b.hex).distance(to: hexToRGB(hex))
        }
    }
}

// MARK: - Harmony Strip
private struct HarmonyStrip: View {
    let base: RGB
    let mode: HarmonyMode
    let onTap: (RGB) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(colors(for: mode), id: \.hex) { c in
                Button {
                    onTap(c)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(c.uiColor))
                            .frame(width: 55, height: 55)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                        Text("#\(normalizeHex(c.hex))")
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func colors(for mode: HarmonyMode) -> [RGB] {
        switch mode {
        case .analogous:
            let (h, s, b) = rgbToHSB(base)
            return [hsbToRGB(hue: h - 30, s: s, b: b),
                    base,
                    hsbToRGB(hue: h + 30, s: s, b: b)]
        case .complementary:
            return [base, complementaryColor(for: base)]
        case .triadic:
            let (h, s, b) = rgbToHSB(base)
            return [base,
                    hsbToRGB(hue: h + 120, s: s, b: b),
                    hsbToRGB(hue: h - 120, s: s, b: b)]
        // case .monochromatic:
        //     return monochromaticColors(for: base)
        }
    }
}

// MARK: - Shades & Tints
// MARK: - Shades & Tints
private struct ShadesAndTintsView: View {
    let base: RGB
    let onSelect: (RGB) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(shadesAndTints(for: base), id: \.hex) { c in
                Button {
                    onSelect(c)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(c.uiColor))
                            .frame(width: 55, height: 55)
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        Text("#\(normalizeHex(c.hex))")
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shadesAndTints(for rgb: RGB) -> [RGB] {
        let (h, s, b) = rgbToHSB(rgb)

        // Distribuye los pasos según el rango real de brillo disponible
        let steps: [CGFloat] = [-45, -25, 0, 20, 40]
        var results: [RGB] = []

        for delta in steps {
            let newBrightness = max(0, min(100, b + delta))
            let newColor = hsbToRGB(hue: h, s: s, b: newBrightness)
            results.append(newColor)
        }

        // ✅ Elimina duplicados basándose en HEX normalizado
        let unique = results.reduce(into: [String: RGB]()) { dict, c in
            let key = normalizeHex(c.hex)
            if dict[key] == nil {
                dict[key] = c
            }
        }

        // Devuelve los valores únicos, ordenados de oscuro → claro
        return unique.values.sorted { rgbToHSB($0).b < rgbToHSB($1).b }
    }

}


// MARK: - Contrast Preview
private struct ContrastPreviewView: View {
    let color: RGB

    var body: some View {
        let bg = Color(color.uiColor)
        let contrastToBlack = contrastRatio(fg: .black, bg: color.uiColor)
        let contrastToWhite = contrastRatio(fg: .white, bg: color.uiColor)

        HStack(spacing: 12) {
            contrastCard(text: "Text sample", textColor: .black, contrast: contrastToBlack)
            contrastCard(text: "Text sample", textColor: .white, contrast: contrastToWhite)
        }
    }

    private func contrastCard(text: String, textColor: Color, contrast: Double) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(color.uiColor))
                    .frame(width: 120, height: 70)
                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)

                Text(text)
                    .font(.callout.bold())
                    .foregroundColor(textColor)
            }

            Text(contrastDescription(for: contrast))
                .font(.caption2)
                .foregroundColor(contrast >= 4.5 ? .green : .orange)
        }
    }

    private func contrastDescription(for ratio: Double) -> String {
        if ratio >= 7 { return "Excellent (AAA)" }
        else if ratio >= 4.5 { return "Good (AA)" }
        else { return "Low Contrast" }
    }
}



// MARK: - Value / Info rows
private struct ValueRow: View {
    let label: String
    let value: String
    let color: Color
    let onCopy: (String) -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label).font(.subheadline)
            Spacer(minLength: 10)
            Text(value).font(.body.monospaced())

            Button {
                onCopy(value)
                withAnimation(.spring()) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                    withAnimation(.easeOut) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(copied ? .green : .secondary)
                    .transition(.scale.combined(with: .opacity))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline.weight(.medium))
            Spacer()
            Text(value).font(.subheadline)
        }
    }
}

// MARK: - Share sheet
struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Math & conversions
private func rgbToHSB(_ rgb: RGB) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
    var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
    UIColor(red: CGFloat(rgb.r)/255, green: CGFloat(rgb.g)/255, blue: CGFloat(rgb.b)/255, alpha: 1)
        .getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
    return (hue*360, sat*100, bri*100)
}

private func rgbToCMYK(_ rgb: RGB) -> (c: CGFloat, m: CGFloat, y: CGFloat, k: CGFloat) {
    let r = CGFloat(rgb.r)/255, g = CGFloat(rgb.g)/255, b = CGFloat(rgb.b)/255
    let k = 1 - max(r, max(g, b))
    if k == 1 { return (0, 0, 0, 100) }
    let c = (1 - r - k) / (1 - k)
    let m = (1 - g - k) / (1 - k)
    let y = (1 - b - k) / (1 - k)
    return (c*100, m*100, y*100, k*100)
}

private func hsbToRGB(hue h: CGFloat, s: CGFloat, b: CGFloat) -> RGB {
    let H = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
    let S = max(0, min(100, s)) / 100
    let V = max(0, min(100, b)) / 100

    let i = floor(H), f = H - i
    let p = V * (1 - S)
    let q = V * (1 - S * f)
    let t = V * (1 - S * (1 - f))

    let (r, g, bl): (CGFloat, CGFloat, CGFloat)
    switch Int(i) {
    case 0: (r, g, bl) = (V, t, p)
    case 1: (r, g, bl) = (q, V, p)
    case 2: (r, g, bl) = (p, V, t)
    case 3: (r, g, bl) = (p, q, V)
    case 4: (r, g, bl) = (t, p, V)
    default: (r, g, bl) = (V, p, q)
    }

    return RGB(r: Int(round(r * 255)), g: Int(round(g * 255)), b: Int(round(bl * 255)))
}

private func complementaryColor(for rgb: RGB) -> RGB {
    let (h, s, b) = rgbToHSB(rgb)
    return hsbToRGB(hue: h + 180, s: s, b: b)
}

private func monochromaticColors(for rgb: RGB) -> [RGB] {
    let (h, s, b) = rgbToHSB(rgb)
    let steps: [CGFloat] = [-30, -15, 0, 15, 30]
    return steps.map { delta in
        hsbToRGB(hue: h, s: s, b: max(0, min(100, b + delta)))
    }
}

// MARK: - Adaptive background
@ViewBuilder
private func adaptiveCardBackground(_ scheme: ColorScheme) -> some View {
    if scheme == .light {
        Color.clear.background(.ultraThinMaterial)
    } else {
        Color(.systemBackground)
    }
}

// MARK: - Contrast ratio calculation
private func contrastRatio(fg: UIColor, bg: UIColor) -> Double {
    func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func adjust(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * adjust(r) + 0.7152 * adjust(g) + 0.0722 * adjust(b)
    }

    let L1 = luminance(fg)
    let L2 = luminance(bg)
    return (max(L1, L2) + 0.05) / (min(L1, L2) + 0.05)
}


// MARK: - UIColor helper
extension UIColor {
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b)
        return luminance > 0.6
    }
}
