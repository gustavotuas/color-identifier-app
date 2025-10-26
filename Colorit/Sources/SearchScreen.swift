import SwiftUI
import UIKit

// MARK: - Utils

/// Normaliza HEX: quita espacios, "#", y lo pone en UPPERCASE.
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

/// Cache ligera para evitar recalcular uiColor en cada render.
final class UIColorCache {
    static let shared = UIColorCache()
    private let cache = NSCache<NSString, UIColor>()
    private init() {}
    func color(for hex: String) -> UIColor {
        let key = normalizeHex(hex) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let ui = hexToRGB(hex).uiColor
        cache.setObject(ui, forKey: key)
        return ui
    }
}
@inline(__always)
private func uiColor(for hex: String) -> UIColor { UIColorCache.shared.color(for: hex) }

// MARK: - Search engine (incremental, GCD)

final class ColorSearchEngine {
    private var all: [NamedColor]
    private var lastQueryLower = ""
    private var lastQueryHex = ""
    private var lastResults: [NamedColor]
    private let queue = DispatchQueue(label: "ColorSearchEngine.queue", qos: .userInitiated)

    init(allColors: [NamedColor]) {
        self.all = allColors
        self.lastResults = allColors
    }
    func replaceAll(_ colors: [NamedColor]) {
        self.all = colors; lastQueryLower = ""; lastQueryHex = ""; lastResults = colors
    }

    func search(query raw: String, ascending: Bool, completion: @escaping ([NamedColor]) -> Void) {
        let qRaw   = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let qLower = qRaw.lowercased()
        let qHex   = normalizeHex(qRaw)

        queue.async { [weak self] in
            guard let self = self else { return }

            if qLower.isEmpty && qHex.isEmpty {
                let base = self.all.sorted { ascending ? $0.name < $1.name : $0.name > $1.name }
                self.lastQueryLower = qLower; self.lastQueryHex = qHex; self.lastResults = base
                return DispatchQueue.main.async { completion(base) }
            }

            let extendsLower = qLower.hasPrefix(self.lastQueryLower) && qLower.count >= self.lastQueryLower.count
            let extendsHex   = qHex.hasPrefix(self.lastQueryHex) && qHex.count >= self.lastQueryHex.count
            let base: [NamedColor] = (extendsLower || extendsHex) ? self.lastResults : self.all

            var filtered = base.filter { nc in
                if !qLower.isEmpty, nc.name.lowercased().contains(qLower) { return true }
                if !qHex.isEmpty, normalizeHex(nc.hex).contains(qHex) { return true }
                if let brand = nc.vendor?.brand?.lowercased(), !qLower.isEmpty, brand.contains(qLower) { return true }
                if let code = nc.vendor?.code?.lowercased(), !qLower.isEmpty, code.contains(qLower) { return true }
                return false
            }
            filtered.sort { ascending ? $0.name < $1.name : $0.name > $1.name }

            self.lastQueryLower = qLower; self.lastQueryHex = qHex; self.lastResults = filtered
            DispatchQueue.main.async { completion(filtered) }
        }
    }
}



struct SearchScreen: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalogs: CatalogStore

    @Environment(\.colorScheme) var colorScheme

    @State private var query = ""
    @State private var layout: LayoutMode = .grid3
    @State private var ascending = true
    @State private var selection: CatalogSelection = .all
    @State private var showVendorSheet = false
    @State private var visibleCount = 100
    private let batchSize = 100

    @State private var filteredColors: [NamedColor] = []
    @State private var searchEngine: ColorSearchEngine?
    @State private var pendingSearchWorkItem: DispatchWorkItem?

    enum LayoutMode: CaseIterable {
        case list, grid2, grid3, wheel
        var icon: String {
            switch self {
            case .list:  return "list.bullet"
            case .grid2: return "square.grid.2x2"
            case .grid3: return "square.grid.3x2"
            case .wheel: return "circle.grid.cross"
            }
        }
    }

    private var vendorIDs: [CatalogID] { CatalogID.allCases.filter { $0 != .generic } }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Colors")
                .toolbar { toolbarContent }
                .sheet(isPresented: $showVendorSheet) { vendorSheet }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by name, hex, brand or code"
                )
                .onAppear {
                    setupSearchBar(for: colorScheme)
                    initialize()
                }
                .onChange(of: colorScheme) { setupSearchBar(for: $0) }
                .onChange(of: query) { performAsyncFilter($0) }
                .onChange(of: selection) { _ in selectionChanged() }
                .onReceive(catalogs.$loaded) { _ in rebuildEngineAndRefilter() }
        }
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            VStack(spacing: 10) {
                if selection.isFiltered { filterBanner }
                layoutView
            }
        }
    }

    // MARK: - Filter Banner
    @ViewBuilder
    private var filterBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
            Text(selection.filterSubtitle).lineLimit(1)
            Spacer()
            Button {
                withAnimation(.easeInOut) {
                    selection = .all
                    VendorSelectionStorage.save(selection)
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
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.5)))
        .foregroundColor(.blue)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Layout View
    @ViewBuilder
    private var layoutView: some View {
        switch layout {
        case .list:
            listLayout
        case .grid2, .grid3:
            gridLayout
        case .wheel:
            ColorAtlasView(colors: filteredColors)
                .environmentObject(favs)
                .padding(.vertical, 8)
        }
    }

    private var listLayout: some View {
        List(filteredColors.prefix(visibleCount)) { color in
            ColorRow(color: color)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear { handlePagination(color) }
        }
        .listStyle(.plain)
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(filteredColors.prefix(visibleCount)) { color in
                    ColorTile(color: color, layout: layout)
                        .onAppear { handlePagination(color) }
                }
            }
            .padding()
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button { showVendorSheet = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Select vendor")
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                ascending.toggle()
                sortFilteredInPlace()
            } label: {
                Image(systemName: ascending ? "arrow.up" : "arrow.down")
            }

            Button {
                withAnimation(.spring()) { toggleLayout() }
            } label: {
                Image(systemName: layout.icon)
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
                        .shadow(radius: 2)
                }
            }
        }
    }

    // MARK: - Vendor Sheet
    private var vendorSheet: some View {
        VendorListSheet(
            selection: $selection,
            candidates: vendorIDs,
            catalogs: catalogs
        )
        .presentationDetents([.medium, .large])
        .onDisappear {
            preloadForSelection()
            rebuildEngineAndRefilter()
        }
    }

    // MARK: - Helpers
    private func initialize() {
        if let saved = VendorSelectionStorage.load() {
            selection = saved
        }
        preloadForSelection()
        let all = makeColors(for: selection)
        filteredColors = all.sorted { ascending ? $0.name < $1.name : $0.name > $1.name }
        if searchEngine == nil {
            searchEngine = ColorSearchEngine(allColors: all)
        } else {
            searchEngine?.replaceAll(all)
        }
    }

    private func selectionChanged() {
        VendorSelectionStorage.save(selection)
        preloadForSelection()
        rebuildEngineAndRefilter()
    }

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

    private func makeColors(for sel: CatalogSelection) -> [NamedColor] {
        func genericColors() -> [NamedColor] {
            catalog.names.map { n in NamedColor(name: n.name, hex: n.hex, vendor: nil, rgb: nil) }
        }
        switch sel {
        case .all:
            let generic = genericColors()
            let vendors = catalogs.colors(for: Set(vendorIDs))
            return mergeUnique([generic, vendors])
        case .genericOnly:
            return genericColors()
        case .vendor(let id):
            return catalogs.colors(for: [id])
        }
    }

    private func mergeUnique(_ arrays: [[NamedColor]]) -> [NamedColor] {
        var seen = Set<String>()
        var out: [NamedColor] = []
        for arr in arrays {
            for x in arr {
                let key = x.vendor?.code ?? "\(x.name)|\(x.hex.lowercased())"
                if seen.insert(key).inserted { out.append(x) }
            }
        }
        return out
    }

    private func rebuildEngineAndRefilter() {
        let all = makeColors(for: selection)
        if searchEngine == nil { searchEngine = ColorSearchEngine(allColors: all) }
        else { searchEngine?.replaceAll(all) }
        performAsyncFilter(query)
        visibleCount = batchSize
    }

    private func toggleLayout() {
        switch layout {
        case .list: layout = .grid2
        case .grid2: layout = .grid3
        case .grid3: layout = .wheel
        case .wheel: layout = .list
        }
    }

    private var gridColumns: [GridItem] {
        switch layout {
        case .grid2: return Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
        case .grid3: return Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        default:     return [GridItem(.flexible())]
        }
    }

    private func handlePagination(_ color: NamedColor) {
        if color.id == filteredColors.prefix(visibleCount).last?.id { loadMore() }
    }

    private func loadMore() {
        guard visibleCount < filteredColors.count else { return }
        visibleCount += batchSize
    }

    // MARK: - SearchBar dynamic theme
    private func setupSearchBar(for scheme: ColorScheme) {
        let field = UISearchBar.appearance().searchTextField
        switch scheme {
        case .dark:
            field.backgroundColor = UIColor.systemGray5
            field.textColor = .white
            field.attributedPlaceholder = NSAttributedString(
                string: "Search by name, hex, brand or code",
                attributes: [.foregroundColor: UIColor.lightGray]
            )
        case .light:
            field.backgroundColor = UIColor.systemGray6
            field.textColor = .black
            field.attributedPlaceholder = NSAttributedString(
                string: "Search by name, hex, brand or code",
                attributes: [.foregroundColor: UIColor.gray]
            )
        @unknown default:
            break
        }
    }

    private func performAsyncFilter(_ query: String) {
        pendingSearchWorkItem?.cancel()
        let work = DispatchWorkItem { [query, ascending] in
            guard let engine = searchEngine else { return }
            engine.search(query: query, ascending: ascending) { result in
                self.filteredColors = result
                self.sortFilteredInPlace()
                self.visibleCount = self.batchSize
            }
        }
        pendingSearchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func sortFilteredInPlace() {
        func key(_ c: NamedColor) -> String {
            let brand = c.vendor?.brand ?? ""
            let code  = c.vendor?.code  ?? ""
            return "\(c.name)|\(brand)|\(code)|\(normalizeHex(c.hex))"
        }
        if ascending {
            filteredColors.sort { key($0) < key($1) }
        } else {
            filteredColors.sort { key($0) > key($1) }
        }
    }
}


struct ColorRow: View {
    @EnvironmentObject var favs: FavoritesStore
    let color: NamedColor
    @State private var showDetail = false
    @State private var tapCount = 0

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor(for: color.hex)))
                .frame(width: 45, height: 45)

            VStack(alignment: .leading, spacing: 4) {
                Text(color.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(color.hex)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let brand = color.vendor?.brand, let code = color.vendor?.code {
                        Text("• \(brand) \(code)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // ✅ Botón tipo Spotify
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    toggleFavorite()
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(isFavoriteNormalized ? Color.clear : Color(red: 179/255, green: 179/255, blue: 179/255), lineWidth: 1.4)
                        .background(
                            Circle()
                                .fill(isFavoriteNormalized ? Color(red: 30/255, green: 215/255, blue: 96/255) : Color.clear)
                        )
                        .frame(width: 15, height: 15)

                    Image(systemName: isFavoriteNormalized ? "checkmark" : "plus")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(isFavoriteNormalized ? .black : Color(red: 179/255, green: 179/255, blue: 179/255))
                }
                .scaleEffect(isFavoriteNormalized ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isFavoriteNormalized)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())

        // ✅ Doble tap para like / unlike
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                toggleFavorite()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        // 👆 Tap simple para abrir detalle (separado)
        .onTapGesture(count: 1) {
            showDetail = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        .sheet(isPresented: $showDetail) {
            ColorDetailView(color: color)
                .environmentObject(favs)
        }
    }

    // MARK: - Helpers
    private func toggleFavorite() {
        let rgb = hexToRGB(color.hex)
        if isFavoriteNormalized {
            favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
        } else {
            let exists = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            if !exists { favs.add(color: rgb) }
        }
    }

    private var isFavoriteNormalized: Bool {
        let key = normalizeHex(color.hex)
        return favs.colors.contains { normalizeHex($0.color.hex) == key }
    }
}


struct ColorTile: View {
    @EnvironmentObject var favs: FavoritesStore
    @Environment(\.colorScheme) var colorScheme
    let color: NamedColor
    let layout: SearchScreen.LayoutMode
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {

                // Fondo del color principal (solo gestiona los taps grandes)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor(for: color.hex)))
                    .frame(height: layout == .grid3 ? 90 : 120)
                    .contentShape(Rectangle()) // asegura área de toque completa
                    .simultaneousGesture( // ✅ combinamos gestos sin bloquear el botón
                        TapGesture(count: 2).onEnded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                toggleFavorite()
                            }
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                    )
                    .onTapGesture(count: 1) {
                        showDetail = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                // ✅ Botón tipo Spotify — ahora responde sin retraso
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        toggleFavorite()
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(isFavoriteNormalized ? Color.clear : Color(red: 179/255, green: 179/255, blue: 179/255), lineWidth: 1.4)
                            .background(
                                Circle()
                                    .fill(isFavoriteNormalized ? Color(red: 30/255, green: 215/255, blue: 96/255) : Color.clear)
                            )
                            .frame(width: 15, height: 15)
                            .contentShape(Circle())

                        Image(systemName: isFavoriteNormalized ? "checkmark" : "plus")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(isFavoriteNormalized ? .black : Color(red: 179/255, green: 179/255, blue: 179/255))
                    }
                    .scaleEffect(isFavoriteNormalized ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isFavoriteNormalized)
                    .padding(6)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle()) // 👈 hace que capture el tap antes del fondo
                .highPriorityGesture( // 👈 prioriza el toque del botón
                    TapGesture().onEnded {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            toggleFavorite()
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                    }
                )
            }

            // Info del color
            VStack(spacing: 1) {
                Text(color.name).font(.caption.bold()).lineLimit(1)
                HStack(spacing: 4) {
                    Text(color.hex).font(.caption2).foregroundColor(.secondary)
                    if let brand = color.vendor?.brand, let code = color.vendor?.code {
                        Text("• \(brand) \(code)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                colorScheme == .dark
                ? Color.white.opacity(0.04)
                : Color.black.opacity(0.01)
            )
            .cornerRadius(10)
        }
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showDetail) {
            ColorDetailView(color: color)
                .environmentObject(favs)
        }
    }

    // MARK: - Helpers
    private func toggleFavorite() {
        let rgb = hexToRGB(color.hex)
        if isFavoriteNormalized {
            favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
        } else {
            let exists = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            if !exists { favs.add(color: rgb) }
        }
    }

    private var isFavoriteNormalized: Bool {
        let key = normalizeHex(color.hex)
        return favs.colors.contains { normalizeHex($0.color.hex) == key }
    }
}

