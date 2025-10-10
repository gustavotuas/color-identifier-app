import SwiftUI
import Combine
import UIKit   // <- necesario para UIColor y NSCache

// MARK: - Helpers

/// Normaliza HEX: quita espacios, "#", y lo pone en UPPERCASE.
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

/// Cache muy simple para no recalcular nearestName(to:) en cada render.
final class NearestNameCache {
    static let shared = NearestNameCache()
    private var cache: [String: String] = [:] // key: HEX normalizado, value: nombre
    private init() {}

    func name(for rgb: RGB, catalog: Catalog) -> String? {
        let key = normalizeHex(rgb.hex)
        if let hit = cache[key] { return hit }
        let name = catalog.nearestName(to: rgb)?.name
        if let name { cache[key] = name }
        return name
    }
}



/// Helper global para obtener UIColor desde HEX (con cache).
@inline(__always)
private func uiColor(for hex: String) -> UIColor {
    UIColorCache.shared.color(for: hex)
}

// MARK: - Models

struct FavoriteColor: Identifiable, Codable, Equatable {
    var id: String { color.hex }
    let color: RGB
    let date: Date
}

struct FavoritePalette: Identifiable, Codable, Equatable {
    let id: String
    let colors: [RGB]
    let date: Date

    init(colors: [RGB]) {
        self.id = colors.map { $0.hex }.joined(separator: "-")
        self.colors = colors
        self.date = Date()
    }
}

// MARK: - Store

@MainActor
final class FavoritesStore: ObservableObject {
    @Published var colors: [FavoriteColor] = []
    @Published var palettes: [FavoritePalette] = []

    private let colorsKey = "favorites_colors_v1"
    private let palettesKey = "favorites_palettes_v1"

    init() { load() }

    func add(color: RGB) {
        if !colors.contains(where: { $0.color.hex == color.hex }) {
            colors.insert(FavoriteColor(color: color, date: Date()), at: 0)
            persist()
        }
    }

    func add(palette: [RGB]) {
        let pal = FavoritePalette(colors: palette)
        if !palettes.contains(pal) {
            palettes.insert(pal, at: 0)
            persist()
        }
    }

    func removeColor(_ color: FavoriteColor) {
        if let index = colors.firstIndex(of: color) {
            colors.remove(at: index)
            persist()
        }
    }

    func removePalette(_ pal: FavoritePalette) {
        if let index = palettes.firstIndex(of: pal) {
            palettes.remove(at: index)
            persist()
        }
    }

    func clearAll() {
        colors.removeAll()
        palettes.removeAll()
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        if let dataColors = try? encoder.encode(colors) {
            UserDefaults.standard.set(dataColors, forKey: colorsKey)
        }
        if let dataPalettes = try? encoder.encode(palettes) {
            UserDefaults.standard.set(dataPalettes, forKey: palettesKey)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        if let dataColors = UserDefaults.standard.data(forKey: colorsKey),
           let decodedColors = try? decoder.decode([FavoriteColor].self, from: dataColors) {
            colors = decodedColors
        }
        if let dataPalettes = UserDefaults.standard.data(forKey: palettesKey),
           let decodedPalettes = try? decoder.decode([FavoritePalette].self, from: dataPalettes) {
            palettes = decodedPalettes
        }
    }
}

// MARK: - FavoritesScreen

struct FavoritesScreen: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var catalog: Catalog

    @State private var query = ""
    @State private var ascending = true
    @State private var showClearAlert = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    // Filtra por name, hex y RGB; usa cache y precomputa claves de orden.
    private var filteredColors: [FavoriteColor] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var nameMap: [String: String] = [:]
        nameMap.reserveCapacity(favs.colors.count)

        let filtered = favs.colors.filter { fav in
            let hexLC = fav.color.hex.lowercased()
            let rgbLC = fav.color.rgbText.lowercased()
            let name  = NearestNameCache.shared.name(for: fav.color, catalog: catalog)
            if let name { nameMap[fav.color.hex] = name }
            return q.isEmpty || hexLC.contains(q) || rgbLC.contains(q) || (name?.lowercased().contains(q) ?? false)
        }

        return filtered.sorted { a, b in
            let na = nameMap[a.color.hex] ?? a.color.hex
            let nb = nameMap[b.color.hex] ?? b.color.hex
            return ascending ? (na < nb) : (na > nb)
        }
    }

    private var filteredPalettes: [FavoritePalette] {
        favs.palettes.filter { pal in
            query.isEmpty || pal.colors.contains {
                $0.hex.lowercased().contains(query.lowercased()) ||
                $0.rgbText.lowercased().contains(query.lowercased())
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // 🎨 Favorite Colors
                    if !filteredColors.isEmpty {
                        Text("Favorite Colors")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(filteredColors) { item in
                                FavoriteColorTile(item: item)
                                    .environmentObject(catalog)
                                    .environmentObject(favs)
                                    .environmentObject(store)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // 🧩 Favorite Palettes
                    if !filteredPalettes.isEmpty {
                        Text("Favorite Palettes")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 16) {
                            ForEach(filteredPalettes) { pal in
                                FavoritePaletteTile(palette: pal)
                                    .environmentObject(favs)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Empty state
                    if filteredColors.isEmpty && filteredPalettes.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "heart.slash")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No favorites yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Save colors and palettes to revisit them here.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 100)
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Favorites")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !filteredColors.isEmpty {
                        Button {
                            ascending.toggle()
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        } label: {
                            Image(systemName: ascending ? "arrow.up" : "arrow.down")
                        }
                    }
                    if !favs.colors.isEmpty || !favs.palettes.isEmpty {
                        Button(role: .destructive) {
                            showClearAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
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
                        }
                    }
                }
            }
            .alert("Clear all favorites?", isPresented: $showClearAlert) {
                Button("Yes", role: .destructive) {
                    withAnimation {
                        favs.clearAll()
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    }
                }
                Button("No", role: .cancel) {}
            } message: {
                Text("This will permanently delete all your favorite colors and palettes.")
            }
            .searchable(text: $query, prompt: "Search favorites by name or hex")
        }
    }
}

// MARK: - FavoriteColorTile

struct FavoriteColorTile: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @State private var selectedColor: NamedColor?   // para el sheet/detalle

    let item: FavoriteColor

    private var isFavorite: Bool {
        let key = normalizeHex(item.color.hex)
        return favs.colors.contains { normalizeHex($0.color.hex) == key }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor(for: item.color.hex)))
                    .frame(height: 90)
                    .onTapGesture {
                        if let found = catalog.nearestName(to: item.color) {
                            selectedColor = found
                        } else {
                            selectedColor = makeNamedColor(from: item)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .contextMenu {
                        Button {
                            toggleFavorite()
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        } label: {
                            Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                  systemImage: isFavorite ? "heart.slash" : "heart")
                        }
                    }

                Button {
                    toggleFavorite()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundColor(iconColor(for: item.color.hex))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                        .scaleEffect(isFavorite ? 1.3 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isFavorite)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 2) {
                Text(item.color.hex.uppercased())
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.color.rgbText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(item: $selectedColor) { c in
            ColorDetailView(color: c)
        }
    }

    // MARK: - Helpers

    private func makeNamedColor(from item: FavoriteColor) -> NamedColor {
        let fixedHex = "#" + normalizeHex(item.color.hex)
        let rgb = hexToRGB(fixedHex)
        return NamedColor(
            name: "Custom Color",
            hex: fixedHex,
            vendor: nil,                  // no viene de proveedor
            rgb: [rgb.r, rgb.g, rgb.b]    // o pon nil si no lo necesitas
        )
    }

    private func toggleFavorite() {
        let rgb = hexToRGB(item.color.hex)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if isFavorite {
                favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            } else {
                let exists = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
                if !exists { favs.add(color: rgb) }
            }
        }
    }

    private func iconColor(for hex: String) -> Color {
        let rgb = hexToRGB(hex)
        let brightness = (0.299 * Double(rgb.r) + 0.587 * Double(rgb.g) + 0.114 * Double(rgb.b)) / 255.0
        return brightness < 0.5 ? .white.opacity(0.9) : .black.opacity(0.7)
    }
}

// MARK: - FavoritePaletteTile

struct FavoritePaletteTile: View {
    @EnvironmentObject var favs: FavoritesStore
    let palette: FavoritePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(palette.colors, id: \.hex) { c in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(c.uiColor))
                            .frame(width: 48, height: 48)
                    }
                }
            }
            HStack {
                Spacer()
                Button(role: .destructive) {
                    favs.removePalette(palette)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Label("Delete Palette", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.7))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
