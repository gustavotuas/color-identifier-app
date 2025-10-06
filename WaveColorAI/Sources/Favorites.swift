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
    
    init() {
        load()
    }
    
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
    
    func removeColor(at offsets: IndexSet) {
        colors.remove(atOffsets: offsets)
        persist()
    }
    
    func removePalette(at offsets: IndexSet) {
        palettes.remove(atOffsets: offsets)
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

// MARK: - UI

struct FavoritesScreen: View {
    @EnvironmentObject var favs: FavoritesStore
    
    var body: some View {
        List {
            if !favs.colors.isEmpty {
                Section("Favorite Colors") {
                    ForEach(favs.colors) { item in
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(item.color.uiColor))
                                .frame(width: 24, height: 24)
                            Text(item.color.hex)
                            Spacer()
                            Text(item.color.rgbText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete(perform: favs.removeColor)
                }
            }
            
            if !favs.palettes.isEmpty {
                Section("Favorite Palettes") {
                    ForEach(favs.palettes) { pal in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(pal.colors) { c in
                                    VStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(c.uiColor))
                                            .frame(width: 36, height: 36)
                                        Text(c.hex)
                                            .font(.caption2)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .onDelete(perform: favs.removePalette)
                }
            }
            
            if favs.colors.isEmpty && favs.palettes.isEmpty {
                Text("No favorites yet. Save colors and palettes to revisit them here.")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .navigationTitle("Favorites")
    }
}
