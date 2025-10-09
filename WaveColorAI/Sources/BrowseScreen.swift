import SwiftUI

struct BrowseScreen: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var favs: FavoritesStore

    @State private var query = ""
    @State private var layout: LayoutMode = .grid2
    @State private var ascending = true

    enum LayoutMode: CaseIterable {
        case list, grid2, grid3, wheel

        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid2: return "square.grid.2x2"
            case .grid3: return "square.grid.3x2"
            case .wheel: return "circle.grid.cross"
            }
        }
    }

    // MARK: - Filtered + Sorted
    var filtered: [NamedColor] {
        var result = catalog.names.filter { c in
            let rgbText = hexToRGB(c.hex).rgbText.lowercased()
            let rgbNumbers = rgbText.replacingOccurrences(of: "rgb", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: " ", with: "")
            return query.isEmpty
                || c.name.lowercased().contains(query.lowercased())
                || c.hex.lowercased().contains(query.lowercased())
                || rgbNumbers.contains(query.lowercased())
        }

        result.sort { ascending ? $0.name < $1.name : $0.name > $1.name }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    switch layout {
                    case .list:
                        List(filtered) { color in
                            ColorRow(color: color)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)

                    case .grid2, .grid3:
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(filtered) { color in
                                    ColorTile(color: color, layout: layout)
                                }
                            }
                            .padding()
                        }

                    case .wheel:
                        ColorWheelView(colors: filtered)
                            .padding(.vertical, 60)
                    }
                }
                .animation(.easeInOut, value: layout)
            }
            .navigationTitle("Colors")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // 🔁 Sort order
                    Button {
                        ascending.toggle()
                    } label: {
                        Image(systemName: ascending ? "arrow.up" : "arrow.down")
                    }

                    // 🧩 Layout selector
                    Button {
                        withAnimation(.spring()) { toggleLayout() }
                    } label: {
                        Image(systemName: layout.icon)
                    }

                    // 💎 PRO Button
                    if !store.isPro {
                        Button {
                            store.showPaywall = true
                        } label: {
                            HStack(spacing: 4) {
                                //Image(systemName: "diamond.fill")
                                Text("PRO")
                                    .font(.caption.bold())
                            }
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
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search by name, hex or RGB")
            .onAppear {
                UISearchBar.appearance().searchTextField.backgroundColor = UIColor.systemGray5
                UISearchBar.appearance().searchTextField.textColor = .white
                UISearchBar.appearance().searchTextField.attributedPlaceholder =
                    NSAttributedString(string: "Search by name, hex or RGB",
                                       attributes: [.foregroundColor: UIColor.lightGray])
            }
        }
        .sheet(isPresented: $store.showPaywall) {
            PaywallView().environmentObject(store)
        }
    }

    // MARK: - Helpers
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
        default: return [GridItem(.flexible())]
        }
    }
}

struct ColorRow: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @State private var showDetail = false
    let color: NamedColor

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hexToRGB(color.hex).uiColor))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(color.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(color.hex)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundColor(isFavorite ? .pink : .gray)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            showDetail = true
        }
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded { toggleFavorite() }
        )
        .sheet(isPresented: $showDetail) {
            ColorDetailView(color: color)
        }
    }

    private var isFavorite: Bool {
        favs.colors.contains { $0.color.hex == color.hex }
    }

    private func toggleFavorite() {
        let rgb = hexToRGB(color.hex)
        if isFavorite {
            favs.colors.removeAll { $0.color.hex == rgb.hex }
        } else {
            favs.add(color: rgb)
        }
    }
}


// MARK: - Color Tile (Grid)
struct ColorTile: View {
    @EnvironmentObject var favs: FavoritesStore
    let color: NamedColor
    let layout: BrowseScreen.LayoutMode
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hexToRGB(color.hex).uiColor))
                    .frame(height: layout == .grid2 ? 130 : 100)
                    .onTapGesture(count: 1) { showDetail = true }
                    .onTapGesture(count: 2) { toggleFavorite() }

                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .padding(6)
                        .foregroundColor(isFavorite ? .white : .black.opacity(0.7))
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
            }

            VStack(spacing: 2) {
                Text(color.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)
                Text(color.hex)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.6))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showDetail) {
            ColorDetailView(color: color)
        }
    }

    private var isFavorite: Bool {
        favs.colors.contains { $0.color.hex == color.hex }
    }

    private func toggleFavorite() {
        let rgb = hexToRGB(color.hex)
        if isFavorite {
            favs.colors.removeAll { $0.color.hex == rgb.hex }
        } else {
            favs.add(color: rgb)
        }
    }
}



private struct DetailRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
