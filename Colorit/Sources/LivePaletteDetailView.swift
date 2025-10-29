import SwiftUI

struct LivePaletteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @EnvironmentObject var store: StoreVM

    let payload: MatchesPayload

    @State private var toastMessage: String? = nil
    @State private var addedPalette = false
    @State private var ascending = true
    @State private var visibleColors: [RGB] = []
    @State var selection: CatalogSelection = VendorSelectionStorage.load() ?? .all


    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {

                        // MARK: - Header title + save button
                        HStack {
                            Text("Color Matches")
                                .font(.largeTitle.bold())
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // MARK: - Color strip
                        HStack(spacing: 0) {
                            ForEach(payload.colors, id: \.hex) { c in
                                Rectangle()
                                    .fill(Color(uiColor: c.uiColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 0)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.6)
                                    )
                            }
                        }
                        .frame(height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                        .padding(.horizontal)

                        Button {
                            savePalette()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: addedPalette ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .symbolEffect(.bounce, value: addedPalette)
                                Text(addedPalette ? "Added!" : "Add Palette to Collections")
                            }
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.horizontal)

                        // MARK: - List style like SearchScreen
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(payload.colors, id: \.hex) { rgb in
                                let named = nearestNamedColor(for: rgb)
                                LiveColorRow(named: named, rgb: rgb, toast: $toastMessage)
                                    .environmentObject(favs)
                                    //.background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Close")
                        }
                        .font(.headline)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            visibleColors = payload.colors.sorted { ascending ? $0.hex < $1.hex : $0.hex > $1.hex }
        }
        .toast(message: $toastMessage)
    }

    // MARK: - Helpers

    private func savePalette() {
        if store.isPro {
            let unique = Array(Set(payload.colors.map { $0.hex })).compactMap { hexToRGB($0) }
            favs.addPalette(name: "Live Palette", colors: unique)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                addedPalette = true
            }
            toastMessage = "Palette Added to Collections"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation { toastMessage = nil }
                addedPalette = false
            }
        } else {
            store.showPaywall = true
        }
    }

    private func nearestNamedColor(for rgb: RGB) -> NamedColor {
        let pool: [NamedColor]
        switch selection {
        case .all:
            pool = catalog.names + catalogs.colors(for: Set(CatalogID.allCases.filter { $0 != .generic }))
        case .vendor(let id):
            pool = catalogs.colors(for: [id])
        case .genericOnly:
            pool = catalogs.colors(for: [.generic])
        }

        guard let nearest = pool.min(by: {
            hexToRGB($0.hex).distance(to: rgb) < hexToRGB($1.hex).distance(to: rgb)
        }) else {
            return NamedColor(name: rgb.hex, hex: rgb.hex, vendor: nil, rgb: nil)
        }
        return nearest
    }

}


// MARK: - LiveColorRow (list row style similar to SearchScreen)
private struct LiveColorRow: View {
    @EnvironmentObject var favs: FavoritesStore
    let named: NamedColor
    let rgb: RGB
    @Binding var toast: String?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: rgb.uiColor))
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(named.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(named.hex)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let brand = named.vendor?.brand, let code = named.vendor?.code {
                        Text("• \(brand) \(code)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                toggleFavorite()
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(isFavorite ? Color.clear : Color.gray.opacity(0.4), lineWidth: 1.4)
                        .background(
                            Circle()
                                .fill(isFavorite ? Color.green.opacity(0.9) : Color.clear)
                        )
                        .frame(width: 16, height: 16)
                    Image(systemName: isFavorite ? "checkmark" : "plus")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(isFavorite ? .black : .gray)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            toggleFavorite()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private var isFavorite: Bool {
        favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
    }

    private func toggleFavorite() {
        let key = normalizeHex(rgb.hex)
        if favs.colors.contains(where: { normalizeHex($0.color.hex) == key }) {
            favs.colors.removeAll { normalizeHex($0.color.hex) == key }
            toast = "Removed from Collections"
        } else {
            favs.add(color: rgb)
            toast = "Added to Collections"
        }
    }
}


// MARK: - Shared Helper
@inline(__always)
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}
