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
                    // Nombre de la paleta
                    Text(palette.name ?? "")
                        .font(.system(size: 26, weight: .bold))
                        .padding(.top, 10)

                    // Lista de colores vertical
                    ForEach(palette.colors, id: \.hex) { color in
                        HStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(color.uiColor))
                                .frame(width: 70, height: 70)
                            Text(color.hex)
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            Button {
                                removeColor(color)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.bottom)
            }
            .navigationTitle("Palette Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // ✏️ Botón de editar nombre
                    Button {
                        tempName = palette.name ?? ""
                        editingName = true
                    } label: {
                        Image(systemName: "pencil")
                    }

                    // 🗑️ Botón de eliminar paleta
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
                TextField("Palette name", text: $tempName)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle("Rename Palette")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingName = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        palette.name = tempName.trimmingCharacters(in: .whitespacesAndNewlines)
                        favs.updatePalette(palette)
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
