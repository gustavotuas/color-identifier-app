import SwiftUI

// MARK: - PhotoPaletteDetailView (idéntico a LivePaletteDetailView, adaptado para Photo)
struct PhotoPaletteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @EnvironmentObject var store: StoreVM

    /// Usa el mismo modelo que Live: colores detectados (RGB) y, si quieres, matches.
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

                        // MARK: - Header title
                        HStack {
                            Text("Color Matches")
                                .font(.largeTitle.bold())
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // MARK: - Color strip (idéntica)
                        // MARK: - Color strip (idéntica a Live)
                        HStack(spacing: 0) {
                            ForEach(visibleColors, id: \.hex) { c in
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

                        // MARK: - Add Palette Button (Adaptive Native Style) — IDÉNTICO
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

                        // MARK: - Lista estilo Search (idéntica)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(visibleColors, id: \.hex) { rgb in
                                let named = nearestNamedColor(for: rgb)
                                PhotoColorRow(toast: $toastMessage, named: named, rgb: rgb)
                                    .environmentObject(favs)
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
            if visibleColors.isEmpty {
                visibleColors = payload.colors.sorted { ascending ? $0.hex < $1.hex : $0.hex > $1.hex }
            }
        }
        .toast(message: $toastMessage)
    }

    // MARK: - Helpers

    private func savePalette() {
        if store.isPro {
            let unique = Array(Set(payload.colors.map { $0.hex })).compactMap { hexToRGB($0) }

            // 🕒 Timestamp tipo "Oct 29, 2025 • 03:42 AM"
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy • hh:mm a"
            let dateString = formatter.string(from: Date())

            // 🔹 Nombre de la paleta con prefijo "Photo Palette"
            let paletteName = "Photo Palette – \(dateString)"

            favs.addPalette(name: paletteName, colors: unique)

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

// MARK: - PhotoColorRow (idéntica a la LiveColorRow, con mismo feel de favorito y toast)
private struct PhotoColorRow: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @Binding var toast: String?

    let named: NamedColor
    let rgb: RGB
    @State private var likedPulse = false
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
                    }
                }
            }

            Spacer()

            // Botón plus/check con mismo estado visual
            Button {
                handleFavorite()
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
            handleFavorite()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    // Estado actual
    private var isFavorite: Bool {
        favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(named.hex) }
    }

    // Lógica favorita con toast (idéntica)
    private func handleFavorite() {
        let key = normalizeHex(named.hex)

        if favs.colors.contains(where: { normalizeHex($0.color.hex) == key }) {
            favs.colors.removeAll { normalizeHex($0.color.hex) == key }
            toast = "Removed from Collections"
        } else {
            favs.add(color: hexToRGB(named.hex))
            toast = "Added to Collections \(named.name)"
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            likedPulse.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            likedPulse = false
        }

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
