import SwiftUI

struct LikeFavoriteSmallButton: View {
    @EnvironmentObject var favs: FavoritesStore
    let hex: String

    @State private var isFavorite = false
    @State private var animate = false

    var body: some View {
        Button {
            toggleFavorite()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(isFavorite ? Color.clear : Color(red: 179/255, green: 179/255, blue: 179/255), lineWidth: 1.4)
                    .background(
                        Circle()
                            .fill(isFavorite ? Color(red: 30/255, green: 215/255, blue: 96/255) : Color.clear)
                    )
                    .frame(width: 20, height: 20)

                Image(systemName: isFavorite ? "checkmark" : "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isFavorite ? .black : Color(red: 179/255, green: 179/255, blue: 179/255))
            }
            .scaleEffect(animate ? 1.15 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: animate)
        }
        .buttonStyle(.plain)
        .onAppear {
            isFavorite = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(hex) }
        }
    }

    // MARK: - Helpers
    private func toggleFavorite() {
        let rgb = hexToRGB(hex)
        if isFavorite {
            favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            isFavorite = false
        } else {
            let exists = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            if !exists { favs.add(color: rgb) }
            isFavorite = true
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            animate.toggle()
        }
    }
}

@inline(__always)
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}
