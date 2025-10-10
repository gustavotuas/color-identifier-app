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

    // MARK: - Filtering and sorting
    private var filtered: [NamedColor] {
        var result = catalog.names.filter { c in
            let rgbText = hexToRGB(c.hex).rgbText.lowercased()
            let rgbNumbers = rgbText
                .replacingOccurrences(of: "rgb", with: "")
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

    // MARK: - Body
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
                    Button {
                        ascending.toggle()
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
    let color: NamedColor
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hexToRGB(color.hex).uiColor))
                .frame(width: 45, height: 45)

            VStack(alignment: .leading, spacing: 4) {
                Text(color.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(color.hex)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // ❤️ Favorite button (reactive)
            Button {
                toggleFavorite()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 20))
                    .foregroundColor(isFavorite ? .pink : .gray)
                    .animation(.easeInOut(duration: 0.2), value: isFavorite)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            showDetail = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .sheet(isPresented: $showDetail) {
            ColorDetailView(color: color)
                .environmentObject(favs)
        }
    }

    // MARK: - Helpers
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


struct ColorTile: View {
    @EnvironmentObject var favs: FavoritesStore
    let color: NamedColor
    let layout: BrowseScreen.LayoutMode
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // 🎨 Color background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hexToRGB(color.hex).uiColor))
                    .frame(height: layout == .grid3 ? 90 : 120)
                    .onTapGesture {
                        showDetail = true
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

                // ❤️ Favorite button (top right)
                Button {
                    toggleFavorite()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundColor(isFavorite ? .white : .black.opacity(0.7))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 2) {
                Text(color.name)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(color.hex)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .background(Color.white.opacity(0.7))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showDetail) {
            ColorDetailView(color: color)
                .environmentObject(favs)
        }
    }

    // MARK: - Favorite helpers
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

