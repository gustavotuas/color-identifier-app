import SwiftUI
import PhotosUI
import UIKit

// MARK: - UIKit PHPicker wrapper
private struct SystemPhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var image: UIImage?
    let onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: SystemPhotoPicker
        init(_ parent: SystemPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            defer { parent.isPresented = false }
            guard let provider = results.first?.itemProvider else { return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let uiimg = object as? UIImage {
                        // ✅ Normaliza orientación y asegura sRGB para que el mapeo de píxeles sea correcto
                        let fixed = uiimg.normalizedUpSRGB() ?? uiimg
                        DispatchQueue.main.async {
                            self.parent.image = fixed
                            self.parent.onPicked(fixed)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Main View
struct PhotosScreen: View {
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore

    @State private var image: UIImage?
    @State private var palette: [RGB] = []
    @State private var matches: [MatchedSwatch] = []
    @State private var selection: CatalogSelection = .all
    @State private var showVendorSheet = false
    @State private var showSystemPicker = false
    @State private var showPaletteSheet = false
    @State private var showColorPicker = false
    @State private var toastMessage: String? = nil
    @State private var addedToCollection = false
    @State private var addedPalette: Bool = false // Asegúrate de tener este state en la vista


private func savePhotoPalette() {
    // Haptic (idéntico patrón de guardado)
    UIImpactFeedbackGenerator(style: .soft).impactOccurred()

    // TODO: Ajusta la fuente de colores según tu lógica actual.
    // Si ya tienes `matches` y conversión a HEX/NamedColor, mantén eso:
    // Ejemplo: tomamos colores detectados únicos por HEX.
    let finals: [RGB] = matches.map { $0.closest != nil ? hexToRGB($0.closest!.hex) : $0.color }
    let unique = Array(Set(finals.map { $0.hex })).compactMap { hexToRGB($0) }

    // 🕒 Formatear fecha actual (ejemplo: "Oct 29, 2025 • 03:42 AM")
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy • hh:mm a"
    let dateString = formatter.string(from: Date())

    // 🔹 Nombre de la paleta con timestamp
    let paletteName = "Photo Palette – \(dateString)"

    // Guardar en colecciones (usa tu store/favs actual)
    favs.addPalette(name: paletteName, colors: unique)

    // Cambios visuales + toast (idénticos)
    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
        addedPalette = true
    }
    showToast("Palette Added to Collections")

    // Volver al estado normal después de un momento (mismo feel de rebote)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            addedPalette = false
        }
    }
}



    private var vendorIDs: [CatalogID] { CatalogID.allCases.filter { $0 != .generic } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if selection.isFiltered { filterHeader }
                    if !palette.isEmpty { paletteCard }
                    imageSection
                    Spacer(minLength: 60)
                }
                .padding(.top, 10)
            }
            .navigationTitle("photos".localized)
            .toolbar {
                // ⚙️ Botón izquierdo (Filtros)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showVendorSheet = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }

                // ⭐ Botón PRO a la derecha si no es usuario PRO
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.isPro {
                        Button {
                            store.showPaywall = true
                        } label: {
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
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        }
                    }
                }
            }

            .sheet(isPresented: $showVendorSheet) {
                VendorListSheet(selection: $selection,
                                candidates: vendorIDs,
                                catalogs: catalogs)
                    .presentationDetents([.medium, .large])
                    .onDisappear {
                        preloadForSelection()
                        rebuildMatches()
                    }
            }
            .sheet(isPresented: $showPaletteSheet) {
    let detectedColors = matches.map { $0.closest != nil ? hexToRGB($0.closest!.hex) : $0.color }
    let unique = Array(Set(detectedColors.map { $0.hex })).compactMap { hexToRGB($0) }
    let payload = MatchesPayload(colors: unique, sourceImage: image)

    NavigationStack {
        PhotoPaletteDetailView(payload: payload)
            .id("photo_palette_detail_view") // 👈 fuerza identidad única
            .environmentObject(favs)
            .environmentObject(catalog)
            .environmentObject(catalogs)
            .environmentObject(store)
    }
    .presentationDetents([.large])
}




            .fullScreenCover(isPresented: $showSystemPicker) {
                SystemPhotoPicker(isPresented: $showSystemPicker, image: $image) { uiimg in
                    let raw = KMeans.palette(from: uiimg, k: 15)
                    let filtered = removeSimilarColors(from: raw.compactMap { hexToRGB($0.hex) }, threshold: 0.02)
                    palette = sortPalette(filtered)
                    rebuildMatches()
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showColorPicker) {
                if let img = image {
                    ColorPickerView(image: img)
                        .environmentObject(favs)
                }
            }
            .onAppear {
                if let saved = VendorSelectionStorage.load() { selection = saved }
                preloadForSelection()
            }
            .onReceive(catalogs.$loaded) { _ in rebuildMatches() }
            .onChange(of: selection) { _ in
                VendorSelectionStorage.save(selection)
                preloadForSelection()
                rebuildMatches()
            }
            .toast(message: $toastMessage)
        }
    }

    // MARK: - Filter Header
    private var filterHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
            Text(selection.filterSubtitle)
                .lineLimit(1)
            Spacer()
            Button {
                withAnimation(.easeInOut) {
                    selection = .all
                    VendorSelectionStorage.save(selection)
                    rebuildMatches()
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
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
        )
        .foregroundColor(.blue)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    // MARK: - Image Section
    private var imageSection: some View {
        VStack(spacing: 14) {
            if let img = image {
                ZStack(alignment: .top) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(img.size, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 6)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                    HStack {
                        Button {
                            showColorPicker = true
                        } label: {
                            Label("Pick Color", systemImage: "eyedropper")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Button {
                            showSystemPicker = true
                        } label: {
                            Label("Change Photo", systemImage: "photo.on.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Choose an image to find matching colors")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                    Button {
                        showSystemPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("Choose Photo")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    Color(uiColor: UIColor { trait in
                                        trait.userInterfaceStyle == .dark
                                        ? UIColor.systemGray5
                                        : UIColor.systemGray6
                                    })
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    Color(uiColor: UIColor { trait in
                                        trait.userInterfaceStyle == .dark
                                        ? UIColor.white.withAlphaComponent(0.15)
                                        : UIColor.black.withAlphaComponent(0.1)
                                    }),
                                    lineWidth: 0.6
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(showSystemPicker ? 0.96 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: showSystemPicker)
                    .padding(.horizontal)
                    .padding(.top, 10)

                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    // MARK: - Palette Card
private var paletteCard: some View {
    ZStack {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detected Palette").font(.headline)
                Spacer()
                Text("(\(matches.count) colors)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 🎨 Paleta de colores detectados
            HStack(spacing: 0) {
                ForEach(matches, id: \.color.hex) { m in
                    Rectangle()
                        .fill(m.closest != nil
                              ? Color(hexToRGB(m.closest!.hex).uiColor)
                              : Color(m.color.uiColor))
                }
            }
            .frame(height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
            .onTapGesture { showPaletteSheet = true }

            // 💾 Botón Add to Collections con animación visual, haptic y toast (estilo Camera)
            // MARK: - Add Palette Button (Adaptive Native Style) — IDÉNTICO
Button {
    savePhotoPalette()
} label: {
    HStack(spacing: 6) {
        Image(systemName: addedPalette ? "checkmark.circle.fill" : "square.and.arrow.down")
            .font(.system(size: 17, weight: .semibold))
        Text(addedPalette ? "Palette Saved" : "Add Palette to Collections")
            .font(.system(size: 17, weight: .semibold))
    }
    .foregroundColor(Color.accentColor)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                Color(uiColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark
                    ? UIColor.systemGray5 // más claro en dark
                    : UIColor.systemGray6 // más neutro en light
                })
            )
            .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
                Color(uiColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark
                    ? UIColor.white.withAlphaComponent(0.15)
                    : UIColor.black.withAlphaComponent(0.1)
                }),
                lineWidth: 0.6
            )
    )
}
.buttonStyle(.plain)
.scaleEffect(addedPalette ? 0.96 : 1.0)
.animation(.spring(response: 0.25, dampingFraction: 0.7), value: addedPalette)
.padding(.horizontal)
.padding(.top, 10)

        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .padding(.horizontal)

        // 🔒 Overlay con blur más fuerte en el centro y suave en los bordes
        if !store.isPro {
            ZStack {
                // Capa base con blur y material
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 10)
                    .opacity(0.95)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.0), location: 0.0),
                                .init(color: .white.opacity(1.0), location: 0.4),
                                .init(color: .white.opacity(1.0), location: 0.6),
                                .init(color: .white.opacity(1.0), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal)

                // Botón de desbloqueo mágico
                MagicalUnlockButton()
                    .onTapGesture { store.showPaywall = true }
            }
            .transition(.opacity)
        }
    }
}


    // MARK: - Magical Unlock Button (slightly larger, perfect balance)
    private struct MagicalUnlockButton: View {
        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .white.opacity(0.4), radius: 3, y: 1)

                Text("Unlock Full Palette")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(
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
                    .clipShape(Capsule())
                    .shadow(color: Color.purple.opacity(0.35), radius: 6, y: 3)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Helpers
    fileprivate struct MatchedSwatch { let color: RGB; let closest: NamedColor? }

    private func preloadForSelection() {
        switch selection {
        case .all:
            catalogs.load(.generic)
            vendorIDs.forEach { catalogs.load($0) }
        case .genericOnly:
            catalogs.load(.generic)
        case .vendor(let id):
            catalogs.load(id)
        }
    }

    private func rebuildMatches() {
        guard !palette.isEmpty else { matches = []; return }
        let pool: [NamedColor]
        switch selection {
        case .all:
            let generic = catalogs.loaded[.generic] ?? catalog.names
            let vendors = catalogs.colors(for: Set(vendorIDs))
            pool = generic + vendors
        case .genericOnly:
            pool = catalogs.loaded[.generic] ?? catalog.names
        case .vendor(let id):
            pool = catalogs.loaded[id] ?? []
        }

        var tempMatches = palette.map { rgb in
            let closest = pool.min(by: {
                hexToRGB($0.hex).distance(to: rgb) < hexToRGB($1.hex).distance(to: rgb)
            })
            return MatchedSwatch(color: rgb, closest: closest)
        }

        var seen: Set<String> = []
        tempMatches.removeAll { match in
            if let hex = match.closest?.hex, seen.contains(hex) {
                return true
            } else {
                if let hex = match.closest?.hex { seen.insert(hex) }
                return false
            }
        }

        matches = tempMatches
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { toastMessage = nil }
        }
    }



    private func removeSimilarColors(from colors: [RGB], threshold: Double) -> [RGB] {
        var unique: [RGB] = []
        for color in colors {
            if !unique.contains(where: { $0.distance(to: color) < threshold }) {
                unique.append(color)
            }
        }
        return unique
    }
}

// MARK: - Detected Palette Sheet + ColorDetailView
private struct DetectedPaletteSheet: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore

    let matches: [PhotosScreen.MatchedSwatch]
    @State private var selectedColor: NamedColor?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(matches, id: \.color.hex) { m in
                        let display = m.closest
                        Button {
                            if let named = display {
                                selectedColor = named
                            }
                        } label: {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(display != nil ? hexToRGB(display!.hex).uiColor : m.color.uiColor))
                                    .frame(width: 80, height: 80)
                                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(display?.name ?? "Unnamed Color")
                                        .font(.headline)
                                    if let brand = display?.vendor?.brand {
                                        Text(brand)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Text((display?.hex ?? m.color.hex).uppercased())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Palette Colors")
            .sheet(item: $selectedColor) { color in
                ColorDetailView(color: color)
                    .environmentObject(favs)
                    .environmentObject(catalog)
                    .environmentObject(catalogs)
                    .presentationDetents([.large])
            }
        }
    }
}

// MARK: - Color Picker View (blur detrás si PRO, encima si no)
import SwiftUI
import UIKit

struct ColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var store: StoreVM
    let image: UIImage

    @State private var pickedColor: UIColor = .white
    @State private var hexValue: String = "#FFFFFF"
    @State private var touchPoint: CGPoint? = nil
    @State private var toastMessage: String? = nil

    // Zoom y paneo
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let containerSize = geo.size
                let fitRect = aspectFitRect(imageSize: image.size, in: containerSize)

                // Imagen principal
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: containerSize.width, height: containerSize.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = offset },
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(lastScale * value, 1.0), 4.0)
                                }
                                .onEnded { _ in lastScale = scale }
                        )
                    )

                // Sampleo de color
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let pScreen = value.location
                                touchPoint = pScreen
                                let centered = CGPoint(x: pScreen.x - containerSize.width/2,
                                                       y: pScreen.y - containerSize.height/2)
                                let unscaled = CGPoint(x: centered.x / scale, y: centered.y / scale)
                                let afterScale = CGPoint(x: unscaled.x + containerSize.width/2,
                                                         y: unscaled.y + containerSize.height/2)
                                let pBase = CGPoint(x: afterScale.x - offset.width,
                                                    y: afterScale.y - offset.height)
                                if fitRect.contains(pBase) {
                                    let rel = CGPoint(x: round(pBase.x - fitRect.minX),
                                                      y: round(pBase.y - fitRect.minY))
                                    if let color = image.getPixelColor(at: rel, in: fitRect) {
                                        pickedColor = color
                                        hexValue = color.toHexString()
                                    }
                                }
                            }
                    )

                // 🎯 Indicador visual del color seleccionado mejorado
                if let p = touchPoint {
                    ZStack {
                        // Sombra difusa para destacar sobre fondos claros u oscuros
                        Circle()
                            .fill(Color.black.opacity(0.25))
                            .frame(width: 46, height: 46)
                            .blur(radius: 2)

                        // Anillo principal con color seleccionado
                        Circle()
                            .strokeBorder(Color(pickedColor), lineWidth: 4)
                            .background(Circle().fill(Color.white.opacity(0.8)))
                            .frame(width: 38, height: 38)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)

                        // Punto central (el píxel exacto de muestreo)
                        Circle()
                            .fill(Color(pickedColor))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.2))

                        // Icono guía de precisión
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isColorLight(pickedColor) ? .black : .white)
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    }
                    .position(p)
                    .animation(.easeInOut(duration: 0.12), value: p)
                }

            }

            // MARK: - Contenedor inferior
            VStack {
                Spacer()
                ZStack {
                    // Fondo blur detrás (siempre visible)
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .blur(radius: 35)
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white.opacity(0.0), location: 0.0),
                                    .init(color: .white.opacity(1.0), location: 0.3),
                                    .init(color: .white.opacity(1.0), location: 0.7),
                                    .init(color: .white.opacity(0.0), location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                        .frame(width: 250, height: 160)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        .opacity(0.8)

                    // 🎨 Contenido (color + hex + Save)
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(pickedColor))
                            .frame(width: 70, height: 70)
                            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)

                        // HEX legible
                        Text(hexValue.uppercased())
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        isColorLight(pickedColor)
                                        ? Color.black.opacity(0.35)
                                        : Color.white.opacity(0.25)
                                    )
                            )
                            .foregroundColor(isColorLight(pickedColor) ? .white : .black)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)

                        // 🎯 Nuevo botón estilo "Pick Color"
                        Button {
                            if store.isPro {
                                let rgb = hexToRGB(hexValue)
                                favs.add(color: rgb)
                                showToast("Color Added to Collections")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    dismiss()
                                }
                            } else {
                                store.showPaywall = true
                            }
                        } label: {
                            Label("Add Color", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .opacity(1)
                    .zIndex(1)

                    // Blur encima SOLO si no es PRO
                    if !store.isPro {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .blur(radius: 10)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .white.opacity(0.0), location: 0.0),
                                        .init(color: .white.opacity(1.0), location: 0.3),
                                        .init(color: .white.opacity(1.0), location: 0.7),
                                        .init(color: .white.opacity(1.0), location: 1.0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .frame(width: 250, height: 160)
                            .opacity(0.99)
                            .zIndex(2)

                        // 🔒 Botón Unlock encima
                        MagicalUnlockButtonSmall(title: "Unlock Picker")
                            .onTapGesture { store.showPaywall = true }
                            .zIndex(3)
                    }
                }
                .padding(.bottom, 36)
            }

            // MARK: - Botón Close (lado derecho)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Close")
                                .font(.headline.weight(.semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.5))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 60)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)

        }
        .background(Color.black.opacity(0.9))
        .ignoresSafeArea()
        .toast(message: $toastMessage)
    }

    // MARK: - Helpers
    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2)
        return CGRect(origin: origin, size: size)
    }

    private func isColorLight(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { toastMessage = nil }
        }
    }

}

// MARK: - Mini botón PRO
private struct MagicalUnlockButtonSmall: View {
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .white.opacity(0.3), radius: 2, y: 1)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#3C8CE7"),
                    Color(hex: "#6F3CE7"),
                    Color(hex: "#C63DE8"),
                    Color(hex: "#FF61B6")
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: .purple.opacity(0.35), radius: 5, y: 3)
    }
}

// MARK: - UIImage pixel color extraction (CORREGIDO)
extension UIImage {
    func getPixelColor(at point: CGPoint, in viewBounds: CGRect) -> UIColor? {
        // point: coordenadas relativas dentro de fitRect (no pantalla completa)
        guard let cgImage = self.cgImage, viewBounds.width > 0, viewBounds.height > 0 else { return nil }

        // Mapea punto relativo -> coordenadas de pixel reales del CGImage
        let px = Int((point.x / viewBounds.width)  * CGFloat(cgImage.width))
        let py = Int((point.y / viewBounds.height) * CGFloat(cgImage.height))

        // Clamps seguros
        let x = max(0, min(cgImage.width  - 1, px))
        let y = max(0, min(cgImage.height - 1, py))

        // Flip vertical (CoreGraphics suele tener origen en la esquina inferior izquierda)
        let yFlipped = cgImage.height - 1 - y

        // Contexto 1x1 RGBA8 sRGB para leer el pixel exacto
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(
            data: &pixel,
            width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        // Dibujamos de modo que (x, yFlipped) caiga en (0,0) del contexto 1x1
        ctx.translateBy(x: -CGFloat(x), y: -CGFloat(yFlipped))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0
        let a = CGFloat(pixel[3]) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    /// Normaliza orientación a .up y asegura espacio de color sRGB RGBA8
    func normalizedUpSRGB() -> UIImage? {
        guard let cg = self.cgImage else { return nil }
        if imageOrientation == .up { return self }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: cg.width,
            height: cg.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var transform = CGAffineTransform.identity

        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform
                .translatedBy(x: CGFloat(cg.width), y: CGFloat(cg.height))
                .rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform
                .translatedBy(x: CGFloat(cg.width), y: 0)
                .rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform
                .translatedBy(x: 0, y: CGFloat(cg.height))
                .rotated(by: -.pi / 2)
        default: break
        }

        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform
                .translatedBy(x: CGFloat(cg.width), y: 0)
                .scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform
                .translatedBy(x: CGFloat(cg.height), y: 0)
                .scaledBy(x: -1, y: 1)
        default: break
        }

        ctx.concatenate(transform)

        let drawRect: CGRect
        if imageOrientation == .left || imageOrientation == .leftMirrored ||
           imageOrientation == .right || imageOrientation == .rightMirrored {
            drawRect = CGRect(x: 0, y: 0, width: cg.height, height: cg.width)
        } else {
            drawRect = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        }

        ctx.draw(cg, in: drawRect)
        guard let fixedCG = ctx.makeImage() else { return nil }
        return UIImage(cgImage: fixedCG, scale: 1, orientation: .up)
    }
}

// MARK: - UIColor to Hex
extension UIColor {
    func toHexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255)
        return String(format: "#%06X", rgb)
    }
}

// MARK: - RGB Luminosity Helper
extension RGB {
    var luminance: Double {
        let red = Double(r)
        let green = Double(g)
        let blue = Double(b)
        return (0.299 * red) + (0.587 * green) + (0.114 * blue)
    }
}

// MARK: - Hex Color Initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
