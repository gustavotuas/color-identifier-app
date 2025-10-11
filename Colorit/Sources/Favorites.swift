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
    @EnvironmentObject var catalogs: CatalogStore     // para vendors

    @State private var ascending = true
    @State private var showClearAlert = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    private var sortedColors: [FavoriteColor] {
        let result = favs.colors.sorted {
            ascending ? $0.color.hex < $1.color.hex : $0.color.hex > $1.color.hex
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // 🎨 Favorite Colors
                    if !sortedColors.isEmpty {
                        Text("Favorite Colors")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(sortedColors) { item in
                                FavoriteColorTile(item: item)
                                    .environmentObject(catalog)
                                    .environmentObject(catalogs)
                                    .environmentObject(favs)
                                    .environmentObject(store)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // 🧩 Favorite Palettes
                    if !favs.palettes.isEmpty {
                        Text("Favorite Palettes")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 16) {
                            ForEach(favs.palettes) { pal in
                                FavoritePaletteTile(palette: pal)
                                    .environmentObject(favs)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Empty state
                    if sortedColors.isEmpty && favs.palettes.isEmpty {
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
                    if !sortedColors.isEmpty {
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
        }
    }
}

// MARK: - FavoriteColorTile

struct FavoriteColorTile: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @State private var selectedColor: NamedColor?

    let item: FavoriteColor

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor(for: item.color.hex)))
                    .frame(height: 90)
                    .onTapGesture {
                        selectedColor = makeNamedColor(from: item)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                // ❎ Botón discreto para eliminar favorito
                Button {
                    removeFavorite()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(6)
                        .background(Color.black.opacity(0.15), in: Circle())
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 2) {
                Text(makeNamedColor(from: item).name)
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

        // Buscar en catálogo genérico
        if let exact = catalog.names.first(where: { normalizeHex($0.hex) == normalizeHex(fixedHex) }) {
            return exact
        }

        // Buscar en todos los catálogos de vendors
        for id in CatalogID.allCases where id != .generic {
            let vendorColors = catalogs.colors(for: [id])
            if let exact = vendorColors.first(where: { normalizeHex($0.hex) == normalizeHex(fixedHex) }) {
                return exact
            }
        }

        // Si no se encuentra
        return NamedColor(
            name: item.color.hex.uppercased(),
            hex: fixedHex,
            vendor: nil,
            rgb: [rgb.r, rgb.g, rgb.b]
        )
    }

    private func removeFavorite() {
        withAnimation(.easeInOut(duration: 0.25)) {
            favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(item.color.hex) }
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                    Image(systemName: "trash")
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
