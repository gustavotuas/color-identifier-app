import SwiftUI

struct PaletteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @EnvironmentObject var store: StoreVM

    @State var palette: FavoritePalette
    @State private var isEditing = false
    @State private var showAddColorSheet = false
    @State private var showDeleteConfirm = false
    @State private var selectedColor: NamedColor?
    @State private var toastMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: - Palette name
                        if isEditing {
                            TextField("Palette name", text: $palette.name.bound)
                                .font(.system(size: 26, weight: .bold))
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal)
                                .padding(.top, 10)
                        } else {
                            Text(palette.name ?? "")
                                .font(.system(size: 26, weight: .bold))
                                .padding(.horizontal)
                                .padding(.top, 10)
                        }

                        // MARK: - Color Strip (Live style)
                        HStack(spacing: 0) {
                            ForEach(palette.colors, id: \.hex) { c in
                                Rectangle()
                                    .fill(Color(c.uiColor))
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

                        // MARK: - Add color button (modern style)
                        if isEditing {
                            Button {
                                showAddColorSheet = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 17, weight: .semibold))
                                    Text("Add Color")
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
                            .padding(.horizontal)
                        }

                        Divider().padding(.horizontal)

                        // MARK: - Color List (Live style + delete in edit mode)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(palette.colors, id: \.hex) { rgb in
                                let named = makeNamedColor(from: rgb)

                                HStack(spacing: 12) {
                                    if isEditing {
                                        Button {
                                            removeColor(rgb)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.system(size: 22))
                                        }
                                        .transition(.opacity.combined(with: .slide))
                                    }

                                    PaletteColorRow(
                                        toast: $toastMessage,
                                        named: named,
                                        rgb: rgb
                                    )
                                    .environmentObject(favs)
                                    .environmentObject(catalog)
                                    .environmentObject(catalogs)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                                .padding(.horizontal)
                                .animation(.easeInOut(duration: 0.25), value: palette.colors)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "Cancel" : "Edit") {
                        withAnimation(.easeInOut) {
                            isEditing.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button {
                            saveChanges()
                            withAnimation { isEditing = false }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Done")
                                    .font(.headline)
                            }
                        }
                    } else {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .alert("Delete this palette?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    withAnimation {
                        favs.removePalette(palette)
                    }
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showAddColorSheet) {
                AddColorsToPaletteSheet(
                    palette: $palette,
                    showSheet: $showAddColorSheet
                )
                .environmentObject(favs)
                .presentationDetents([.medium, .large])
            }
            .toast(message: $toastMessage)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers
    private func saveChanges() {
        favs.updatePalette(palette)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func removeColor(_ color: RGB) {
        if let idx = palette.colors.firstIndex(of: color) {
            withAnimation(.easeInOut(duration: 0.25)) {
                palette.colors.remove(at: idx)
            }
            favs.updatePalette(palette)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            if palette.colors.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    favs.removePalette(palette)
                    dismiss()
                }
            }
        }
    }

    private func makeNamedColor(from rgb: RGB) -> NamedColor {
        let fixedHex = "#" + rgb.hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalized = fixedHex.replacingOccurrences(of: "#", with: "")
        let rgbValues = hexToRGB(fixedHex)

        if let exact = catalog.names.first(where: { $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized }) {
            return exact
        }

        for id in CatalogID.allCases where id != .generic {
            let vendorColors = catalogs.colors(for: [id])
            if let exact = vendorColors.first(where: { $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized }) {
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

// MARK: - Row Style (Like LiveColorRow)
private struct PaletteColorRow: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @Binding var toast: String?

    let named: NamedColor
    let rgb: RGB
    @State private var likedPulse = false

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { likedPulse = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { toast = nil }
    }
}

// MARK: - Add Colors Sheet
struct AddColorsToPaletteSheet: View {
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore
    @Binding var palette: FavoritePalette
    @Binding var showSheet: Bool
    @State private var selectedColors: Set<String> = []

    private var availableColors: [FavoriteColor] {
        favs.colors.filter { fav in
            !palette.colors.contains(where: { $0.hex == fav.color.hex })
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if availableColors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("All colors already added.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                } else {
                    Text("Select colors to add")
                        .font(.headline)
                        .padding(.top)

                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(availableColors) { fav in
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

                    Button(action: addSelectedColors) {
                        Label("Add \(selectedColors.count) Color\(selectedColors.count == 1 ? "" : "s")",
                              systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedColors.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                    .disabled(selectedColors.isEmpty)
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSheet = false
                    }
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

    private func addSelectedColors() {
        let selected = favs.colors
            .filter { selectedColors.contains($0.color.hex) }
            .map { $0.color }
        palette.colors.append(contentsOf: selected)
        favs.updatePalette(palette)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showSheet = false
    }

    private func makeNamedColor(from rgb: RGB) -> NamedColor {
        let fixedHex = "#" + rgb.hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalized = fixedHex.replacingOccurrences(of: "#", with: "")
        let rgbValues = hexToRGB(fixedHex)

        if let exact = catalog.names.first(where: { $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized }) {
            return exact
        }

        for id in CatalogID.allCases where id != .generic {
            let vendorColors = catalogs.colors(for: [id])
            if let exact = vendorColors.first(where: { $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized }) {
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

@inline(__always)
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

extension Optional where Wrapped == String {
    var bound: String {
        get { self ?? "" }
        set { self = newValue }
    }
}
