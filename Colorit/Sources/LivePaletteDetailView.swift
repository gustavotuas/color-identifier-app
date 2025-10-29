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

                        // MARK: - Add Palette Button (Adaptive Native Style)
                        Button {
                            savePalette()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: addedPalette ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .font(.system(size: 17, weight: .semibold))
                                Text(addedPalette ? "Palette Saved" : "Add Palette to Collections")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundColor(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        Color(uiColor: UIColor { trait in
                                            trait.userInterfaceStyle == .dark
                                            ? UIColor.systemGray5 // más claro en dark
                                            : UIColor.systemGray6 // más neutro en light
                                        })
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        Color(uiColor: UIColor { trait in
                                            trait.userInterfaceStyle == .dark
                                            ? UIColor.white.withAlphaComponent(0.15)
                                            : UIColor.black.withAlphaComponent(0.1)
                                        }),
                                        lineWidth: 0.6
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(addedPalette ? 0.96 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: addedPalette)
                        .padding(.horizontal)
                        .padding(.top, 10)




                        Divider().padding(.horizontal)

                        // MARK: - List style like SearchScreen
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(payload.colors, id: \.hex) { rgb in
                                let named = nearestNamedColor(for: rgb)
                                LiveColorRow(toast: $toastMessage, named: named, rgb: rgb)
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
// MARK: - LiveColorRow (Enhanced with match + CameraScreen logic)
private struct LiveColorRow: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @Binding var toast: String?
    @State private var likedPulse = false

    let named: NamedColor
    let rgb: RGB
    @State var selection: CatalogSelection = VendorSelectionStorage.load() ?? .all

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
                            .lineLimit(1)
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
                        .strokeBorder(
                            isFavorite ? Color.green.opacity(0.8) : Color.gray.opacity(0.4),
                            lineWidth: 1.4
                        )
                        .background(
                            Circle()
                                .fill(isFavorite ? Color.green.opacity(0.9) : Color.clear)
                        )
                        .frame(width: 22, height: 22)

                    Image(systemName: isFavorite ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isFavorite ? .white : .gray)
                        .symbolEffect(.bounce, value: likedPulse)
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

    // MARK: - Favorite state
    private var isFavorite: Bool {
        favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
    }

    // MARK: - Save logic identical to CameraScreen
    private func toggleFavorite() {
        let key = normalizeHex(rgb.hex)

        // Pool de colores según filtro actual
        let pool: [NamedColor]
        switch selection {
        case .all:
            pool = catalog.names + catalogs.colors(for: Set(CatalogID.allCases.filter { $0 != .generic }))
        case .vendor(let id):
            pool = catalogs.colors(for: [id])
        case .genericOnly:
            pool = catalogs.colors(for: [.generic])
        }

        // Buscar coincidencia más cercana
        guard let nearest = pool.min(by: {
            hexToRGB($0.hex).distance(to: rgb) < hexToRGB($1.hex).distance(to: rgb)
        }) else {
            toast = "No match found"
            return
        }

        // Calcular precisión
        let diff = rgb.distance(to: hexToRGB(nearest.hex))
        let maxDiff = sqrt(3 * pow(255.0, 2.0))
        let precision = max(0, 1 - diff / maxDiff) * 100

        // Guardar o eliminar
        if favs.colors.contains(where: { normalizeHex($0.color.hex) == normalizeHex(nearest.hex) }) {
            favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(nearest.hex) }
            toast = "Removed from Collections"
        } else {
            favs.add(color: hexToRGB(nearest.hex))
            toast = "Added to Collections \(nearest.name) (\(Int(precision))%)"
        }

        // Animación
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
            likedPulse.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) { likedPulse = false }
        }

        // Ocultar toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            toast = nil
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
