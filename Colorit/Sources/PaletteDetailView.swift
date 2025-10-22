import SwiftUI

struct PaletteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore
    @EnvironmentObject var catalog: Catalog
    @EnvironmentObject var catalogs: CatalogStore

    @State var palette: FavoritePalette
    @State private var isEditing = false
    @State private var showAddColorSheet = false
    @State private var showDeleteConfirm = false
    @State private var selectedColor: NamedColor?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {

                    // MARK: - Paleta nombre
                    if isEditing {
                        TextField("Palette name", text: $palette.name.bound)
                            .font(.system(size: 26, weight: .bold))
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                    } else {
                        Text(palette.name ?? "")
                            .font(.system(size: 26, weight: .bold))
                            .padding(.horizontal)
                    }

                    // MARK: - Franja de colores
                    HStack(spacing: 0) {
                        ForEach(palette.colors, id: \.hex) { c in
                            Rectangle()
                                .fill(Color(c.uiColor))
                        }
                    }
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)

                    Divider().padding(.horizontal)

                    // MARK: - Add color button
                    if isEditing {
                        HStack(spacing: 8) {
                            Button {
                                showAddColorSheet = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label("Add Color", systemImage: "plus.circle.fill")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }

                    // MARK: - Lista de colores
                    VStack(spacing: 12) {
                        ForEach(palette.colors, id: \.hex) { color in
                            let named = makeNamedColor(from: color)
                            HStack(spacing: 14) {
                                if isEditing {
                                    Button {
                                        removeColor(color)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.system(size: 22))
                                    }
                                }

                                Button {
                                    selectedColor = named
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                } label: {
                                    HStack(spacing: 14) {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(color.uiColor))
                                            .frame(width: 70, height: 70)
                                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(named.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)

                                            Text(color.hex.uppercased())
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            if let vendor = named.vendor?.brand {
                                                Text("\(vendor)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
                .padding(.bottom)
            }
            .navigationTitle("")
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
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 22))
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
            .sheet(item: $selectedColor) { color in
                ColorDetailView(color: color)
                    .environmentObject(favs)
                    .environmentObject(catalog)
                    .environmentObject(catalogs)
                    .presentationDetents([.large])
            }
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

                                ZStack(alignment: .topTrailing) {
                                    VStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(fav.color.uiColor))
                                            .frame(height: 100)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                                            )
                                            .onTapGesture {
                                                toggleSelection(fav.color.hex)
                                            }

                                        VStack(spacing: 2) {
                                            Text(named.name)
                                                .font(.caption.bold())
                                                .foregroundColor(.primary)
                                                .lineLimit(1)

                                            Text(fav.color.hex.uppercased())
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            if let brand = named.vendor?.brand {
                                                Text(brand)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.bottom, 4)
                                    }

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.accentColor)
                                            .padding(6)
                                    }
                                }
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


extension Optional where Wrapped == String {
    var bound: String {
        get { self ?? "" }
        set { self = newValue }
    }
}
