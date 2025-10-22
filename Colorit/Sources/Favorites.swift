import SwiftUI
import Combine
import UIKit

// MARK: - Helpers

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
    var name: String?
    var colors: [RGB]
    let date: Date

    init(colors: [RGB], name: String? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        self.date = Date()
        self.id = colors.map { $0.hex }.joined(separator: "-") + formatter.string(from: date)
        self.colors = colors
        self.name = name ?? "Palette \(formatter.string(from: date))"
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
        palettes.insert(pal, at: 0)
        persist()
    }

    func updatePalette(_ pal: FavoritePalette) {
        if let idx = palettes.firstIndex(where: { $0.id == pal.id }) {
            palettes[idx] = pal
            persist()
            objectWillChange.send()
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
    @EnvironmentObject var catalogs: CatalogStore

    @State private var ascending = true
    @State private var showClearAlert = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    private var sortedColors: [FavoriteColor] {
        favs.colors.sorted {
            ascending ? $0.color.hex < $1.color.hex : $0.color.hex > $1.color.hex
        }
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

                        VStack(spacing: 20) {
                            ForEach(favs.palettes) { pal in
                                FavoritePaletteTile(palette: pal)
                                    .environmentObject(favs)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Empty State
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

    private func makeNamedColor(from item: FavoriteColor) -> NamedColor {
        let fixedHex = "#" + normalizeHex(item.color.hex)
        let rgb = hexToRGB(fixedHex)
        if let exact = catalog.names.first(where: { normalizeHex($0.hex) == normalizeHex(fixedHex) }) {
            return exact
        }
        for id in CatalogID.allCases where id != .generic {
            let vendorColors = catalogs.colors(for: [id])
            if let exact = vendorColors.first(where: { normalizeHex($0.hex) == normalizeHex(fixedHex) }) {
                return exact
            }
        }
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
        favs.objectWillChange.send()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

// MARK: - FavoritePaletteTile
struct FavoritePaletteTile: View {
    @EnvironmentObject var favs: FavoritesStore
    let palette: FavoritePalette
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Nombre de la paleta
            Text(palette.name ?? "Unnamed Palette")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 6)

            // Barra de colores continua
            HStack(spacing: 0) {
                ForEach(palette.colors, id: \.hex) { c in
                    Rectangle()
                        .fill(Color(c.uiColor))
                }
            }
            .frame(height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showDetail = true
                }
            }

            // Cantidad de colores
            Text("\(palette.colors.count) \(palette.colors.count == 1 ? "Color" : "Colors")")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                showDetail = true
            }
        }
        .sheet(isPresented: $showDetail) {
            PaletteDetailView(palette: palette)
                .environmentObject(favs)
        }
    }
}
