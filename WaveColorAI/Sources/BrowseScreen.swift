import SwiftUI

struct BrowseScreen: View {
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var favs: FavoritesStore

    @State private var query = ""
    @State private var layout: LayoutMode = .grid2
    @State private var ascending = true

    // 🔹 Lazy loading
    @State private var visibleCount = 100
    private let batchSize = 100

    // 🔹 Async filtering
    @State private var filteredColors: [NamedColor] = []
    @State private var queryTask: Task<Void, Never>? = nil

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

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    switch layout {
                    case .list:
                        List(filteredColors.prefix(visibleCount)) { color in
                            ColorRow(color: color)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .onAppear { handlePagination(color) }
                        }
                        .listStyle(.plain)

                    case .grid2, .grid3:
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(filteredColors.prefix(visibleCount)) { color in
                                    ColorTile(color: color, layout: layout)
                                        .onAppear { handlePagination(color) }
                                }
                            }
                            .padding()
                        }

                    case .wheel:
                        ColorWheelView(colors: filteredColors.prefix(visibleCount).map { $0 })
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
                        sortFiltered()
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
                        prompt: "Search by name or hex")
            .onAppear {
                setupSearchBar()
                filteredColors = sortedCatalog()
            }
            .onChange(of: query) { newValue in
                performAsyncFilter(newValue)
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

    private func handlePagination(_ color: NamedColor) {
        if color.id == filteredColors.prefix(visibleCount).last?.id {
            loadMore()
        }
    }

    private func loadMore() {
        guard visibleCount < filteredColors.count else { return }
        visibleCount += batchSize
    }

    private func setupSearchBar() {
        UISearchBar.appearance().searchTextField.backgroundColor = UIColor.systemGray5
        UISearchBar.appearance().searchTextField.textColor = .white
        UISearchBar.appearance().searchTextField.attributedPlaceholder =
            NSAttributedString(string: "Search by name or hex",
                               attributes: [.foregroundColor: UIColor.lightGray])
    }

    private func performAsyncFilter(_ query: String) {
        queryTask?.cancel()
        queryTask = Task {
            let q = query.lowercased().trimmingCharacters(in: .whitespaces)
            var result: [NamedColor]

            if q.isEmpty {
                result = sortedCatalog()
            } else {
                result = catalog.names.filter {
                    $0.name.lowercased().contains(q) ||
                    $0.hex.lowercased().contains(q)
                }
                result.sort { ascending ? $0.name < $1.name : $0.name > $1.name }
            }

            await MainActor.run {
                filteredColors = result
                visibleCount = batchSize
            }
        }
    }

    private func sortFiltered() {
        filteredColors.sort { ascending ? $0.name < $1.name : $0.name > $1.name }
    }

    private func sortedCatalog() -> [NamedColor] {
        catalog.names.sorted { ascending ? $0.name < $1.name : $0.name > $1.name }
    }
}

// MARK: - ColorRow
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

// MARK: - ColorTile
struct ColorTile: View {
    @EnvironmentObject var favs: FavoritesStore
    let color: NamedColor
    let layout: BrowseScreen.LayoutMode
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
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

                Button {
                    toggleFavorite()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundColor(iconColor(for: color))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                        .scaleEffect(isFavorite ? 1.3 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isFavorite)
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

    private func iconColor(for named: NamedColor) -> Color {
        let rgb = hexToRGB(named.hex)
        let brightness = (0.299 * Double(rgb.r) + 0.587 * Double(rgb.g) + 0.114 * Double(rgb.b)) / 255.0
        if isFavorite {
            return brightness < 0.5 ? .red : .red.opacity(0.9)
        } else {
            return brightness < 0.5 ? .white.opacity(0.9) : .black.opacity(0.7)
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
