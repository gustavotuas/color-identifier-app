import SwiftUI
import PhotosUI

struct PhotosScreen: View {
    // MARK: - Environment
    @EnvironmentObject var store: StoreVM
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore

    // MARK: - State
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var palette: [RGB] = []
    @State private var matches: [MatchedSwatch] = []

    @State private var selection: CatalogSelection = .all
    @State private var showVendorSheet = false

    @State private var showToast = false
    @State private var toastMessage = ""

    private var vendorIDs: [CatalogID] { CatalogID.allCases.filter { $0 != .generic } }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 10) {

                    // Banner de filtro activo — idéntico a SearchScreen
                    if selection.isFiltered {
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // MARK: - Main content
                    ScrollView {
                        VStack(spacing: 18) {
                            if let _ = image {
                                paletteCard
                                savePaletteButton
                            }

                            imageSection

                            Spacer(minLength: 60)
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .navigationTitle("Photo Colours")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { showVendorSheet = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Select vendor")
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
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
            .sheet(isPresented: $showVendorSheet) {
                VendorListSheet(
                    selection: $selection,
                    candidates: vendorIDs,
                    catalogs: catalogs
                )
                .presentationDetents([.medium, .large])
                .onDisappear {
                    preloadForSelection()
                    rebuildMatches()
                }
            }
            .sheet(isPresented: $store.showPaywall) {
                PaywallView().environmentObject(store)
            }
            .onAppear {
                if let saved = VendorSelectionStorage.load() { selection = saved }
                preloadForSelection()
            }
            .onReceive(catalogs.$loaded) { _ in rebuildMatches() }
            .onChange(of: selection) { _ in
                VendorSelectionStorage.save(selection)
                preloadForSelection()
                rebuildMatches()
            }
            .onChange(of: item) { _, newValue in
                Task {
                    guard let data = try? await newValue?.loadTransferable(type: Data.self),
                          let img = UIImage(data: data) else { return }
                    image = img
                    palette = KMeans.palette(from: img, k: 10)
                    rebuildMatches()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .overlay(alignment: .top) {
                if showToast {
                    Text(toastMessage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showToast)
        }
    }

    // MARK: - Palette Card
    private var paletteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected Palette")
                .font(.headline)
                .padding(.horizontal, 16)

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .frame(height: 150)
                    .padding(.horizontal, 16)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 3)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(matches.enumerated()), id: \.offset) { _, m in
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(uiColor: m.color.uiColor))
                                    .frame(width: 82, height: 82)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.22), lineWidth: 1)
                                    )
                                    .onTapGesture {
                                        if store.isPro {
                                            UIPasteboard.general.string = "\(m.color.hex) | \(m.color.rgbText)"
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            showToast("Copied: \(m.color.hex)")
                                        } else {
                                            store.showPaywall = true
                                        }
                                    }

                                Group {
                                    if store.isPro {
                                        Text(m.closest?.name ?? m.color.hex)
                                    } else {
                                        Text(m.color.hex)
                                            .redacted(reason: .placeholder)
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(width: 82)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(store.isPro)

                if !store.isPro {
                    VisualEffectBlur(style: .systemThinMaterialLight)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .frame(height: 150)
                        .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        Label("Unlock Full Results", systemImage: "lock.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                        Button {
                            store.showPaywall = true
                        } label: {
                            Text("Unlock PRO")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(colors: [.purple, .pink],
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing)
                                )
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        Text("\(palette.count) Colours")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
        }
    }

    // MARK: - Save Palette
    private var savePaletteButton: some View {
        Group {
            if palette.isEmpty {
                EmptyView()
            } else if store.isPro {
                Button {
                    favs.add(palette: palette)
                    showToast("Palette saved to Favorites")
                } label: {
                    Label("Save Palette", systemImage: "heart.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
            } else {
                Button { store.showPaywall = true } label: {
                    Label("Save Palette", systemImage: "heart")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Image Section
    private var imageSection: some View {
        VStack(spacing: 14) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 6)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                PhotosPicker(selection: $item, matching: .images) {
                    Label("Change Photo", systemImage: "photo.on.rectangle")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a photo to discover its colors")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)

                    PhotosPicker(selection: $item, matching: .images) {
                        Text("Choose Photo")
                            .font(.headline)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    // MARK: - Data / Matching
    private struct MatchedSwatch {
        let color: RGB
        let closest: NamedColor?
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

    private func activeColors() -> [NamedColor] {
        func genericColors() -> [NamedColor] {
            if let loaded = catalogs.loaded[.generic] { return loaded }
            return catalog.names
        }
        switch selection {
        case .all:
            let generic = genericColors()
            let vendors = catalogs.colors(for: Set(vendorIDs))
            return mergeUnique([generic, vendors])
        case .genericOnly:
            return genericColors()
        case .vendor(let id):
            return catalogs.loaded[id] ?? []
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

    private func rebuildMatches() {
        guard !palette.isEmpty else { matches = []; return }
        let pool = activeColors()
        matches = palette.map { rgb in
            let closest = nearest(in: pool, to: rgb)
            return MatchedSwatch(color: rgb, closest: closest)
        }
    }

    private func nearest(in pool: [NamedColor], to target: RGB) -> NamedColor? {
        var best: NamedColor?
        var bestD = Double.greatestFiniteMagnitude
        for nc in pool {
            let d = hexToRGB(nc.hex).distance(to: target)
            if d < bestD { bestD = d; best = nc }
        }
        return best
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Blur helper
private struct VisualEffectBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
