import SwiftUI
import UIKit

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
    @State private var toastMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

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

                        // MARK: - Color Strip
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

                        // MARK: - Add color button
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
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(uiColor: UIColor { trait in
                                            trait.userInterfaceStyle == .dark
                                            ? UIColor.systemGray5 : UIColor.systemGray6
                                        }))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }

                        Divider().padding(.horizontal)

                        // MARK: - Color List
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
                        withAnimation { isEditing.toggle() }
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
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    } else {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: { Image(systemName: "trash") }
                    }
                }
            }
            .alert("Delete this palette?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    withAnimation { favs.removePalette(palette) }
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showAddColorSheet) {
                AddColorsToPaletteSheet(palette: $palette, showSheet: $showAddColorSheet)
                    .environmentObject(favs)
                    .presentationDetents([.medium, .large])
            }
            .toast(message: $toastMessage)
        }
    }

    // MARK: - Helpers
    private func saveChanges() {
        favs.updatePalette(palette)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func removeColor(_ color: RGB) {
        if let idx = palette.colors.firstIndex(of: color) {
            withAnimation { palette.colors.remove(at: idx) }
            favs.updatePalette(palette)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func makeNamedColor(from rgb: RGB) -> NamedColor {
        let fixedHex = "#" + rgb.hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalized = fixedHex.replacingOccurrences(of: "#", with: "")
        if let exact = catalog.names.first(where: { $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized }) {
            return exact
        }
        for id in CatalogID.allCases where id != .generic {
            if let exact = catalogs.colors(for: [id]).first(where: {
                $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized
            }) {
                return exact
            }
        }
        let rgbValues = hexToRGB(fixedHex)
        return NamedColor(name: rgb.hex.uppercased(), hex: fixedHex, vendor: nil,
                          rgb: [rgbValues.r, rgbValues.g, rgbValues.b])
    }
}

// MARK: - Palette Row
private struct PaletteColorRow: View {
    @EnvironmentObject var favs: FavoritesStore
    @Binding var toast: String?
    let named: NamedColor
    let rgb: RGB

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: rgb.uiColor))
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(named.name).font(.headline).lineLimit(1)
                Text(named.hex).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Add Colors Sheet (grid3 estilo SearchScreen)
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
        Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if availableColors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.largeTitle).foregroundColor(.green)
                        Text("All colors already added.").font(.headline).foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                } else {
                    Text("Select colors to add")
                        .font(.title3.bold())
                        .padding(.top)

                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 18) {
                            ForEach(availableColors) { fav in
                                let named = makeNamedColor(from: fav.color)
                                SelectableColorTileGrid3(
                                    color: named,
                                    isSelected: selectedColors.contains(fav.color.hex),
                                    toggle: { toggleSelection(fav.color.hex) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
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
                    Button("Cancel") { showSheet = false }
                }
            }
        }
    }

    // MARK: - Helpers
    private func toggleSelection(_ hex: String) {
        if selectedColors.contains(hex) { selectedColors.remove(hex) }
        else { selectedColors.insert(hex) }
    }

    private func addSelectedColors() {
        let selected = favs.colors.filter { selectedColors.contains($0.color.hex) }.map { $0.color }
        palette.colors.append(contentsOf: selected)
        favs.updatePalette(palette)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showSheet = false
    }

    private func makeNamedColor(from rgb: RGB) -> NamedColor {
        let fixedHex = "#" + rgb.hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalized = fixedHex.replacingOccurrences(of: "#", with: "")
        if let exact = catalog.names.first(where: { $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized }) {
            return exact
        }
        for id in CatalogID.allCases where id != .generic {
            if let exact = catalogs.colors(for: [id]).first(where: {
                $0.hex.replacingOccurrences(of: "#", with: "").uppercased() == normalized
            }) {
                return exact
            }
        }
        let rgbValues = hexToRGB(fixedHex)
        return NamedColor(name: rgb.hex.uppercased(), hex: fixedHex, vendor: nil,
                          rgb: [rgbValues.r, rgbValues.g, rgbValues.b])
    }
}

// MARK: - Grid3 Tile estilo SearchScreen (color arriba, texto debajo)
private struct SelectableColorTileGrid3: View {
    let color: NamedColor
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor(for: color.hex)))
                    .frame(height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                    .onTapGesture { toggle() }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.system(size: 22))
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                }
            }

            VStack(spacing: 1) {
                Text(color.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(color.hex)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let brand = color.vendor?.brand, let code = color.vendor?.code {
                        Text("• \(brand) \(code)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers
@inline(__always)
private func uiColor(for hex: String) -> UIColor {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard let intVal = Int(s, radix: 16) else { return .gray }
    let r = CGFloat((intVal >> 16) & 0xFF) / 255.0
    let g = CGFloat((intVal >> 8) & 0xFF) / 255.0
    let b = CGFloat(intVal & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: 1.0)
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
