import SwiftUI

struct PaletteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore
    @State var palette: FavoritePalette

    @State private var showDeleteAlert = false
    @State private var editingName = false
    @State private var tempName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // MARK: - Nombre de la paleta
                    Text(palette.name ?? "")
                        .font(.system(size: 26, weight: .bold))
                        .padding(.top, 10)

                    // MARK: - Franja superior con todos los colores
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

                    Divider()
                        .padding(.horizontal)

                    // MARK: - Lista de colores vertical
                    VStack(spacing: 12) {
                        ForEach(palette.colors, id: \.hex) { color in
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(color.uiColor))
                                    .frame(width: 70, height: 70)
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(color.hex)
                                        .font(.headline)
                                    Text(color.rgbText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    removeColor(color)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 20))
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
            // ⬇️ Título dinámico con el nombre de la paleta
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // ✏️ Editar nombre
                    Button {
                        tempName = palette.name ?? ""
                        editingName = true
                    } label: {
                        Image(systemName: "pencil")
                    }

                    // 🗑️ Eliminar paleta
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .alert("Delete this palette?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    favs.removePalette(palette)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $editingName) {
                renameSheet
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Rename Sheet
    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Palette Name")) {
                    TextField("Enter new name", text: $tempName)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Rename Palette")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingName = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = tempName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            palette.name = trimmed
                            favs.updatePalette(palette)
                        }
                        editingName = false
                    }
                }
            }
        }
    }

    // MARK: - Helpers
    private func removeColor(_ color: RGB) {
        if let idx = palette.colors.firstIndex(of: color) {
            palette.colors.remove(at: idx)
            favs.updatePalette(palette)
        }
    }
}
