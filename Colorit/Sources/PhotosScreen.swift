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
                        DispatchQueue.main.async {
                            self.parent.image = uiimg
                            self.parent.onPicked(uiimg)
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
    @State private var toastMessage = ""
    @State private var showToast = false

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
            .navigationTitle("Photo Colours")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showVendorSheet = true } label: {
                        Image(systemName: "slider.horizontal.3")
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
                DetectedPaletteSheet(matches: matches)
                    .environmentObject(favs)
                    .environmentObject(catalog)
                    .environmentObject(catalogs)
                    .presentationDetents([.fraction(0.8), .large])
            }
            .fullScreenCover(isPresented: $showSystemPicker) {
                SystemPhotoPicker(isPresented: $showSystemPicker, image: $image) { uiimg in
                    let raw = KMeans.palette(from: uiimg, k: 15)
                    let filtered = removeSimilarColors(from: raw.compactMap { hexToRGB($0.hex) }, threshold: 0.02)
                    palette = filtered
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
            .overlay(alignment: .top) {
                if showToast {
                    Text(toastMessage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showToast)
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
                        .scaledToFit()
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
                    Text("Select a photo to discover its colors")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                    Button("Choose Photo") { showSystemPicker = true }
                        .font(.headline)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    // MARK: - Palette Card
    private var paletteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detected Palette").font(.headline)
                Spacer()
                Text("(\(matches.count) colors)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 0) {
                ForEach(matches, id: \.color.hex) { m in
                    Rectangle()
                        .fill(m.closest != nil ? Color(hexToRGB(m.closest!.hex).uiColor) : Color(m.color.uiColor))
                }
            }
            .frame(height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
            .onTapGesture { showPaletteSheet = true }

            Button {
                if store.isPro {
                    let finals = matches.map { $0.closest != nil ? hexToRGB($0.closest!.hex) : $0.color }
                    let unique = Array(Set(finals.map { $0.hex })).compactMap { hexToRGB($0) }
                    favs.addPalette(name: "Detected Palette", colors: unique)
                    showToast("Palette saved")
                } else {
                    store.showPaywall = true
                }
            } label: {
                Label("Save Palette", systemImage: "heart.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .foregroundColor(.blue)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .padding(.horizontal)
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
        toastMessage = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { showToast = false }
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

// MARK: - Color Picker View (mejorada)
struct ColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore
    let image: UIImage

    @State private var pickedColor: UIColor = .white
    @State private var hexValue: String = "#FFFFFF"
    @State private var touchPoint: CGPoint? = nil

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        touchPoint = location
                        if let color = image.getPixelColor(at: location, in: geo.frame(in: .local)) {
                            pickedColor = color
                            hexValue = color.toHexString()
                        }
                    }

                // 🎯 Target visual con preview del color
                if let point = touchPoint {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(Color(pickedColor))
                            .frame(width: 26, height: 26)
                            .shadow(radius: 3)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .position(point)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: point)
                }
            }

            // 🟣 Panel inferior visible sobre la imagen
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(pickedColor))
                    .frame(width: 80, height: 80)
                    .shadow(radius: 4)
                Text(hexValue)
                    .font(.headline)
                    .foregroundColor(.primary)
                Button("Save to Favorites") {
                    let rgb = hexToRGB(hexValue)
                    favs.add(color: rgb)
                    dismiss()
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .foregroundColor(.white)
            }
            .padding(.bottom, 50)
            .background(
                LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .bottom, endPoint: .top)
                    .ignoresSafeArea(edges: .bottom)
            )
            .frame(maxHeight: .infinity, alignment: .bottom)

            // 🔘 Botón “Close” visible arriba
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .background(Color.black.opacity(0.9))
        .ignoresSafeArea()
    }
}


// MARK: - UIImage pixel color extraction
extension UIImage {
    func getPixelColor(at point: CGPoint, in viewBounds: CGRect) -> UIColor? {
        guard let cgImage = self.cgImage else { return nil }

        let scaleX = CGFloat(cgImage.width) / viewBounds.width
        let scaleY = CGFloat(cgImage.height) / viewBounds.height

        let x = Int(point.x * scaleX)
        let y = Int(point.y * scaleY)
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return nil }

        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
        let r = CGFloat(ptr[offset]) / 255.0
        let g = CGFloat(ptr[offset + 1]) / 255.0
        let b = CGFloat(ptr[offset + 2]) / 255.0
        let a = CGFloat(ptr[offset + 3]) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
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
