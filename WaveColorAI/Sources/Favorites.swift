import SwiftUI
import Combine

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

    private var filteredColors: [FavoriteColor] {
        let filtered = favs.colors.filter { fav in
            query.isEmpty
            || fav.color.hex.lowercased().contains(query.lowercased())
            || fav.color.rgbText.lowercased().contains(query.lowercased())
        }
        return filtered.sorted { a, b in
            let na = catalog.nearestName(to: a.color)?.name ?? a.color.hex
            let nb = catalog.nearestName(to: b.color)?.name ?? b.color.hex
            return ascending ? (na < nb) : (na > nb)
        }
    }

    private var filteredPalettes: [FavoritePalette] {
        favs.palettes.filter { pal in
            query.isEmpty || pal.colors.contains { $0.hex.lowercased().contains(query.lowercased()) }
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
                    // 🔁 Sort
                    if !filteredColors.isEmpty {
                        Button {
                            ascending.toggle()
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        } label: {
                            Image(systemName: ascending ? "arrow.up" : "arrow.down")
                        }
                    }

                    // 🧹 Clear All (Centered alert)
                    if !favs.colors.isEmpty || !favs.palettes.isEmpty {
                        Button(role: .destructive) {
                            showClearAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    // 💎 PRO Button
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
            // ✅ Centered alert with “Yes / No”
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
            .searchable(text: $query, prompt: "Search favorites by hex or RGB")
        }
    }
}

// MARK: - FavoriteColorTile

struct FavoriteColorTile: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var store: StoreVM
    let item: FavoriteColor

    @State private var selectedColor: NamedColor?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(item.color.uiColor))
                    .frame(height: 90)
                    .onTapGesture {
                        if let found = catalog.nearestName(to: item.color) {
                            selectedColor = found
                        } else {
                            let fixedHex = item.color.hex.hasPrefix("#") ? item.color.hex : "#\(item.color.hex)"
                            selectedColor = NamedColor(
                                name: "Custom Color",
                                hex: fixedHex,
                                rgb: item.color.rgbText,
                                group: "Custom",
                                theme: nil
                            )
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                Button {
                    favs.removeColor(item)
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .padding(6)
                        .foregroundColor(.white)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            }

            VStack(spacing: 2) {
                if let name = catalog.nearestName(to: item.color)?.name {
                    Text(name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .foregroundColor(.primary)
                } else {
                    Text("Custom Color")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                }
                Text(item.color.hex)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .background(Color.white.opacity(0.7))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .sheet(item: $selectedColor) { named in
            ColorDetailView(color: named)
                .environmentObject(favs)
        }
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
                    ForEach(palette.colors) { c in
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
