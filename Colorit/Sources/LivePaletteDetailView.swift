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
    @State var selection: CatalogSelection = VendorSelectionStorage.load() ?? .genericOnly


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
                                            ? UIColor.systemGray5
                                            : UIColor.systemGray6
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
                            ForEach(visibleColors, id: \.hex) { rgb in
                                let named = nearestNamedColor(for: rgb)
                                LiveColorRow(toast: $toastMessage, named: named, rgb: rgb)
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

                // MARK: - Blur + Magical Unlock Button (solo si no es Pro)
                if !store.isPro {
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            //.background(Color.black.opacity(0.01))
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .zIndex(10)
                            .animation(.easeInOut(duration: 0.25), value: store.showPaywall)

                        MagicalUnlockButton {
                            // Acción: abrir el paywall
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                store.showPaywall = true
                            }
                        }
                        .zIndex(11)
                    }
                    .allowsHitTesting(true)
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
            visibleColors = sortPalette(payload.colors)
        }
        .toast(message: $toastMessage)
    }

    // MARK: - Helpers

    private func savePalette() {
        if store.isPro {
            let unique = Array(Set(payload.colors.map { $0.hex })).compactMap { hexToRGB($0) }

            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy • hh:mm a"
            let dateString = formatter.string(from: Date())

            let paletteName = "Live Palette – \(dateString)"
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


// MARK: - Magical Unlock Button
private struct MagicalUnlockButton: View {
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .white.opacity(0.4), radius: 3, y: 1)

            Button(action: onTap) {
                Text("Unlock Full Palette & Color Matches")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(hex: "#3C8CE7"),
                                Color(hex: "#6F3CE7"),
                                Color(hex: "#C63DE8"),
                                Color(hex: "#FF61B6")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.purple.opacity(0.35), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }
}



// MARK: - LiveColorRow
private struct LiveColorRow: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @Binding var toast: String?

    let named: NamedColor
    let rgb: RGB
    @State private var likedPulse = false
    @State var selection: CatalogSelection = VendorSelectionStorage.load() ?? .genericOnly

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

    private var isFavorite: Bool {
        favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(named.hex) }
    }

    private func handleFavorite() {
        let key = normalizeHex(named.hex)
        if favs.colors.contains(where: { normalizeHex($0.color.hex) == key }) {
            favs.removeColor(hex: named.hex)
            toast = "Removed from Collections"
        } else {
            favs.add(color: hexToRGB(named.hex))
            toast = "Added to Collections \(named.name)"
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            likedPulse.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { likedPulse = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { toast = nil }
    }
}


// MARK: - Shared Helper
@inline(__always)
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}
