import SwiftUI
import Combine
import UIKit

// MARK: - Helpers
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

final class NearestNameCache {
    static let shared = NearestNameCache()
    private var cache: [String: String] = [:]
    private init() {}

    func name(for rgb: RGB, catalog: Catalog) -> String? {
        let key = normalizeHex(rgb.hex)
        if let hit = cache[key] { return hit }
        let name = catalog.nearestName(to: rgb)?.name
        if let name { cache[key] = name }
        return name
    }
}

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
    @Published var totalFavorites: Int = 0        // sigue mostrando el total (para badge)
    @Published var hasNewFavorites: Bool = false  // 👈 nuevo: controla si hay nuevos no vistos



    private let colorsKey = "favorites_colors_v1"
    private let palettesKey = "favorites_palettes_v1"

    init() { load() }

    func add(color: RGB) {
        if !colors.contains(where: { $0.color.hex == color.hex }) {
            colors.insert(FavoriteColor(color: color, date: Date()), at: 0)
            persist()
            totalFavorites = colors.count
            hasNewFavorites = true // 👈 marca como “nuevo sin revisar”
        }
    }

    func addPalette(name: String?, colors: [RGB]) {
        let ordered = sortPalette(colors)
        let pal = FavoritePalette(colors: ordered, name: name)
        palettes.insert(pal, at: 0)
        persist()
        hasNewFavorites = true // 👈 igual aquí
    }


    func updatePalette(_ pal: FavoritePalette) {
        if let idx = palettes.firstIndex(where: { $0.id == pal.id }) {
            palettes[idx] = pal
            persist()
            objectWillChange.send()
        }
    }

    func removeColor(_ color: FavoriteColor) {
        colors.removeAll { $0 == color }
        persist()
    }

    func removePalette(_ pal: FavoritePalette) {
        palettes.removeAll { $0.id == pal.id }
        persist()
    }

    func clearAll() {
        colors.removeAll()
        palettes.removeAll()
        persist()
        totalFavorites = 0
        hasNewFavorites = false
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
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @EnvironmentObject var store: StoreVM

    @State private var ascending = true
    @State private var showClearAlert = false
    @State private var showNewPaletteSheet = false
    @State private var selectedFilter: FavoritesFilter = .all

    private var gridColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: 3) }

    private var sortedColors: [FavoriteColor] {
        favs.colors.sorted {
            let l1 = 0.2126 * Double($0.color.r) + 0.7152 * Double($0.color.g) + 0.0722 * Double($0.color.b)
            let l2 = 0.2126 * Double($1.color.r) + 0.7152 * Double($1.color.g) + 0.0722 * Double($1.color.b)
            return ascending ? l1 < l2 : l1 > l2
        }
    }


    private var filteredColors: [FavoriteColor] {
        selectedFilter == .all || selectedFilter == .colors ? sortedColors : []
    }

    private var filteredPalettes: [FavoritePalette] {
        selectedFilter == .all || selectedFilter == .palettes ? favs.palettes : []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Filter Bar (dentro del scroll)
                    HStack(spacing: 8) {
                        ForEach(FavoritesFilter.allCases, id: \.self) { filter in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedFilter = filter
                                }
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            } label: {
                                Text(filter.rawValue)
                                    .font(.subheadline.bold())
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 16)
                                    .background(
                                        Capsule()
                                            .fill(selectedFilter == filter
                                                  ? Color.secondary.opacity(0.2)
                                                  : Color.clear)
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                    .foregroundColor(selectedFilter == filter ? .primary : .secondary)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // 🎨 Favorite Colors
                    if !filteredColors.isEmpty {
                        Text("Colors")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(filteredColors) { item in
                                FavoriteColorTile(item: item)
                                    .environmentObject(favs)
                                    .environmentObject(catalog)
                                    .environmentObject(catalogs)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // 🧩 Favorite Palettes
                    if !filteredPalettes.isEmpty {
                        Text("Palettes")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 20) {
                            ForEach(filteredPalettes) { pal in
                                FavoritePaletteTile(palette: pal)
                                    .environmentObject(favs)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Empty State
                    if filteredColors.isEmpty && filteredPalettes.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "heart.slash")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No collections yet")
                                .font(.headline)
                            Text("Save colors and palettes to revisit them here.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {


            Button {
                if store.isPro {
                    showNewPaletteSheet = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    if favs.palettes.isEmpty {
                        // permitir crear una sola paleta para no-Pro
                        showNewPaletteSheet = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } else {
                        // ya tiene una paleta -> mostrar paywall
                        store.showPaywall = true
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
            }


                    // 🔹 Botón de orden (asc/desc)
                    if !sortedColors.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                ascending.toggle()
                            }
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .rotationEffect(.degrees(ascending ? 0 : 180))
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: ascending)
                        }
                        .accessibilityLabel("Sort by alphabetic")
                    }

                    // Limpiar todo
                    if !favs.colors.isEmpty || !favs.palettes.isEmpty {
                        Button(role: .destructive) {
                            showClearAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    // PRO badge
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
            .alert("Clear all Collections?", isPresented: $showClearAlert) {
                Button("Yes", role: .destructive) { favs.clearAll() }
                Button("No", role: .cancel) {}
            }
            .sheet(isPresented: $showNewPaletteSheet) {
                NewPaletteSheet(showSheet: $showNewPaletteSheet)
                    .environmentObject(favs)
                    .environmentObject(catalog)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Filter Enum
enum FavoritesFilter: String, CaseIterable {
    case all = "All"
    case colors = "Colors"
    case palettes = "Palettes"
}


// MARK: - New Palette Sheet
struct NewPaletteSheet: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @Binding var showSheet: Bool

    @State private var selectedColors: Set<String> = []
    @State private var paletteName = ""
    @FocusState private var nameFieldFocused: Bool

    private var gridColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: 3) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Palette name (optional)", text: $paletteName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { hideKeyboard() }

                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(favs.colors) { fav in
                        let isSelected = selectedColors.contains(fav.color.hex)
                        let named = makeNamedColor(from: fav.color)

                        SelectableColorTile(
                            color: fav.color,
                            named: named,
                            isSelected: isSelected,
                            toggle: { toggleSelection(fav.color.hex) }
                        )
                    }

                    }
                    .padding(.horizontal)
                }


                Button(action: createPalette) {
                    Text("Create Palette")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedColors.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .disabled(selectedColors.isEmpty)

                Spacer()
            }
            .navigationTitle("New Palette")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        hideKeyboard()
                        showSheet = false
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    nameFieldFocused = true
                }
            }
        }
    }

    private func toggleSelection(_ hex: String) {
        if selectedColors.contains(hex) {
            selectedColors.remove(hex)
        } else {
            selectedColors.insert(hex)
        }
    }

    private func createPalette() {
        hideKeyboard()
        let selected = favs.colors.filter { selectedColors.contains($0.color.hex) }.map { $0.color }
        favs.addPalette(name: paletteName.isEmpty ? nil : paletteName, colors: selected)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showSheet = false
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Helpers
    private func makeNamedColor(from rgb: RGB) -> NamedColor {
        let fixedHex = "#" + rgb.hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalized = fixedHex.replacingOccurrences(of: "#", with: "")
        let rgbValues = hexToRGB(fixedHex)

        if let exact = catalog.names.first(where: {
            $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized
        }) {
            return exact
        }

        for id in CatalogID.allCases where id != .generic {
            let vendorColors = catalogs.colors(for: [id])
            if let exact = vendorColors.first(where: {
                $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized
            }) {
                return exact
            }
        }

        return NamedColor(
            name: rgb.hex.uppercased(),
            hex: fixedHex,
            vendor: nil,
            rgb: [rgbValues.r, rgbValues.g, rgbValues.b]
        )
    }

}

// MARK: - FavoriteColorTile
struct FavoriteColorTile: View {
    let item: FavoriteColor
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore

    @State private var selectedColor: NamedColor?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor(for: item.color.hex)))
                    .frame(height: 90)
                    .onTapGesture {
                        selectedColor = makeNamedColor(from: item)
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }

                Button {
                    withAnimation {
                        favs.removeColor(item)
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(6)
                }
            }

            // Nombre y HEX
            VStack(spacing: 2) {
                Text(makeNamedColor(from: item).name)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.color.hex.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(item: $selectedColor) { color in
            ColorDetailView(color: color)
                .environmentObject(favs)
                .environmentObject(catalog)
                .environmentObject(catalogs)
                .presentationDetents([.large])
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
}

// MARK: - FavoritePaletteTile
struct FavoritePaletteTile: View {
    let palette: FavoritePalette
    @EnvironmentObject var favs: FavoritesStore

    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(palette.name ?? "Untitled Palette")
                .font(.headline)
                .padding(.horizontal, 4)

            HStack(spacing: 0) {
                ForEach(palette.colors, id: \.hex) { c in
                    Rectangle()
                        .fill(Color(c.uiColor))
                }
            }
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                showDetail = true
            }
            .sheet(isPresented: $showDetail) {
                PaletteDetailView(palette: palette)
                    .environmentObject(favs)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }

            Text("\(palette.colors.count) \(palette.colors.count == 1 ? "Color" : "Colors")")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - SelectableColorTile (igual visual que Search grid3)
struct SelectableColorTile: View {
    let color: RGB
    let named: NamedColor
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(color.uiColor))
                    .frame(height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    )
                    .onTapGesture { toggle() }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                        .padding(6)
                }
            }

            VStack(spacing: 1) {
                Text(named.name)
                    .font(.caption.bold())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(color.hex.uppercased())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let brand = named.vendor?.brand, let code = named.vendor?.code {
                        Text("• \(brand) \(code)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let brand = named.vendor?.brand {
                        Text("• \(brand)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

