import SwiftUI

struct ColorDetailView: View {
    @EnvironmentObject var favs: FavoritesStore
    let color: NamedColor

    private var rgb: RGB { hexToRGB(color.hex) }

    @State private var copiedHex = false
    @State private var copiedRGB = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // MARK: - Header Title
                Text(color.name)
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // MARK: - Color Preview
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(rgb.uiColor))
                    .frame(height: 180)
                    .overlay(
                        VStack {
                            Spacer()
                            Text(color.name)
                                .font(.headline)
                                .foregroundColor(.black)
                            Text(color.hex)
                                .font(.subheadline)
                                .foregroundColor(.black.opacity(0.8))
                            Spacer(minLength: 8)
                        }
                    )
                    .padding(.horizontal)

                // MARK: - Copy Buttons + Favorite
                HStack(spacing: 24) {
                    Button(action: copyHex) {
                        Label("Copy Hex", systemImage: "doc.on.doc")
                            .labelStyle(VerticalLabelStyle())
                    }
                    Button(action: copyRGB) {
                        Label("Copy RGB", systemImage: "doc.on.doc")
                            .labelStyle(VerticalLabelStyle())
                    }
                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundColor(isFavorite ? .pink : .gray)
                    }
                }
                .padding(.top, 10)

                Divider().padding(.vertical, 8)

                // MARK: - RGB Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("RGB Breakdown")
                        .font(.headline)
                        .padding(.bottom, 4)

                    ColorComponentRow(label: "Red", value: rgb.r)
                    ColorComponentRow(label: "Green", value: rgb.g)
                    ColorComponentRow(label: "Blue", value: rgb.b)
                }
                .padding()
                .background(Color(.systemBackground).opacity(0.9))
                .cornerRadius(12)
                .padding(.horizontal)

                // MARK: - Additional Info
                if let theme = color.theme {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Theme")
                            .font(.headline)
                        Text(theme)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                Spacer(minLength: 40)
            }
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            copiedHex = false
            copiedRGB = false
        }
    }

    // MARK: - Helpers

    private func copyHex() {
        UIPasteboard.general.string = color.hex
        copiedHex = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedHex = false
        }
    }

    private func copyRGB() {
        UIPasteboard.general.string = "\(rgb.r), \(rgb.g), \(rgb.b)"
        copiedRGB = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedRGB = false
        }
    }

    private var isFavorite: Bool {
        favs.colors.contains { $0.color.hex == color.hex }
    }

    private func toggleFavorite() {
        let rgb = hexToRGB(color.hex)
        if isFavorite {
            favs.colors.removeAll { $0.color.hex == rgb.hex }
        } else {
            favs.add(color: rgb)
        }
    }
}

// MARK: - Subviews
private struct ColorComponentRow: View {
    let label: String
    let value: Int
    var body: some View {
        HStack {
            Label(label, systemImage: "circle.fill")
                .labelStyle(IconOnlyLabelStyle())
                .foregroundColor(label == "Red" ? .red : label == "Green" ? .green : .blue)
            Text(label)
                .frame(width: 60, alignment: .leading)
            Spacer()
            Text("\(value)")
                .fontWeight(.medium)
            Image(systemName: "doc.on.doc")
                .foregroundColor(.gray)
        }
    }
}

private struct VerticalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack {
            configuration.icon
                .font(.title3)
            configuration.title
                .font(.caption)
        }
        .frame(width: 80)
    }
}
