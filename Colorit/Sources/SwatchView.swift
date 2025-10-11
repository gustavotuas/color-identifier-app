import SwiftUI

/// Vista individual que muestra un color dentro de una paleta
struct SwatchView: View {
    let c: RGB

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: Double(c.r) / 255.0,
                            green: Double(c.g) / 255.0,
                            blue: Double(c.b) / 255.0))
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(radius: 2)

            // Código HEX del color
            Text(c.hexString)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(4)
    }
}

extension RGB {
    /// Convierte RGB a string hexadecimal (#RRGGBB)
    var hexString: String {
        return String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))
    }
}
