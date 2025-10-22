import SwiftUI

struct PaletteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var favs: FavoritesStore
    @State var palette: FavoritePalette

    @State private var showDeleteConfirm = false
    @State private var showRenameAlert = false
    @State private var tempName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // MARK: - Nombre dinámico de la paleta
                    Text(palette.name ?? "")
                        .font(.system(size: 26, weight: .bold))
                        .padding(.top, 10)
                        .id(palette.id) // fuerza refresco visual al actualizar nombre

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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // ✏️ Editar nombre (alerta nativa centrada)
                    Button {
                        tempName = palette.name ?? ""
                        showRenameAlert = true
                    } label: {
                        Image(systemName: "pencil")
                    }

                    // 🗑️ Eliminar paleta (alerta nativa)
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            // 🧠 Alerta nativa centrada para editar nombre
            .textFieldAlert(
                title: "Rename Palette",
                text: $tempName,
                isPresented: $showRenameAlert,
                placeholder: "Enter new name",
                onSave: {
                    let trimmed = tempName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    palette.name = trimmed
                    favs.updatePalette(palette)

                    // Refrescar la vista al instante
                    withAnimation(.easeInOut) {
                        self.palette = favs.palettes.first(where: { $0.id == palette.id }) ?? palette
                    }
                }
            )
            // ⚠️ Confirmación de eliminación
            .alert("Delete this palette?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    withAnimation {
                        favs.removePalette(palette)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers
    private func removeColor(_ color: RGB) {
        if let idx = palette.colors.firstIndex(of: color) {
            palette.colors.remove(at: idx)
            favs.updatePalette(palette)
        }
    }
}

// MARK: - UIViewControllerRepresentable helper para alerta nativa con TextField
extension View {
    func textFieldAlert(
        title: String,
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placeholder: String = "",
        onSave: @escaping () -> Void
    ) -> some View {
        TextFieldAlertHelper(
            title: title,
            text: text,
            isPresented: isPresented,
            placeholder: placeholder,
            onSave: onSave,
            presenting: self
        )
    }
}

private struct TextFieldAlertHelper<Presenting>: UIViewControllerRepresentable where Presenting: View {
    let title: String
    @Binding var text: String
    @Binding var isPresented: Bool
    let placeholder: String
    let onSave: () -> Void
    let presenting: Presenting

    func makeUIViewController(context: Context) -> UIViewController {
        UIHostingController(rootView: presenting)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented else { return }

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = text
            textField.placeholder = placeholder
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .words

            // 👇 Autofoco inmediato
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                textField.becomeFirstResponder()
            }
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            isPresented = false
        })

        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            if let newText = alert.textFields?.first?.text {
                text = newText
                onSave()
            }
            isPresented = false
        })

        DispatchQueue.main.async {
            uiViewController.present(alert, animated: true)
        }
    }
}
