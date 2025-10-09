import SwiftUI
import UIKit

struct ColorDetailView: View {
    @EnvironmentObject var favs: FavoritesStore
    let color: NamedColor

    @State private var selectedTab = "RGB"
    @State private var copiedText: String? = nil
    @State private var showCopyAlert = false

    private var rgb: RGB { hexToRGB(color.hex) }

    private let tabs = ["RGB", "HEX", "HSB", "CMYK"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Title
                Text(color.name)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // MARK: - Color Preview
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(rgb.uiColor))
                    .frame(height: 200)
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
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                    .padding(.horizontal)

                // MARK: - Copy + Favorite Buttons
                HStack(spacing: 20) {
                    CopyButton(label: "Copy HEX", value: color.hex, copiedText: $copiedText)
                    CopyButton(label: "Copy RGB", value: "\(rgb.r),\(rgb.g),\(rgb.b)", copiedText: $copiedText)

                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundColor(isFavorite ? .pink : .gray)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.top, 8)

                // MARK: - Tabs
                Picker("Mode", selection: $selectedTab) {
                    ForEach(tabs, id: \.self) { tab in
                        Text(tab)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedTab) { _ in
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }

                // MARK: - Values
                VStack(spacing: 10) {
                    switch selectedTab {
                    case "RGB":
                        ColorComponentRow(label: "Red", value: rgb.r, color: .red)
                        ColorComponentRow(label: "Green", value: rgb.g, color: .green)
                        ColorComponentRow(label: "Blue", value: rgb.b, color: .blue)

                    case "HEX":
                        ValueRow(label: "Hex", value: color.hex, color: .gray)

                    case "HSB":
                        let (h, s, b) = rgbToHSB(rgb)
                        ValueRow(label: "Hue", value: "\(Int(h))°", color: .orange)
                        ValueRow(label: "Saturation", value: "\(Int(s))%", color: .pink)
                        ValueRow(label: "Brightness", value: "\(Int(b))%", color: .yellow)

                    case "CMYK":
                        let (c, m, y, k) = rgbToCMYK(rgb)
                        ValueRow(label: "Cyan", value: "\(Int(c))%", color: .cyan)
                        ValueRow(label: "Magenta", value: "\(Int(m))%", color: .pink)
                        ValueRow(label: "Yellow", value: "\(Int(y))%", color: .yellow)
                        ValueRow(label: "Black", value: "\(Int(k))%", color: .black)

                    default:
                        EmptyView()
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .padding(.horizontal)

                // MARK: - Theme
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
            .padding(.bottom, 60)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: copiedText) { _ in
            if copiedText != nil {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .overlay(alignment: .bottom) {
            if let copied = copiedText {
                Text("Copied \(copied)")
                    .font(.caption.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(14)
                    .shadow(radius: 4)
                    .transition(.opacity.combined(with: .scale))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            withAnimation { copiedText = nil }
                        }
                    }
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Helpers

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
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // Convert RGB → HSB
    private func rgbToHSB(_ rgb: RGB) -> (CGFloat, CGFloat, CGFloat) {
        let r = CGFloat(rgb.r) / 255
        let g = CGFloat(rgb.g) / 255
        let b = CGFloat(rgb.b) / 255

        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        v = maxVal

        let delta = maxVal - minVal
        s = maxVal == 0 ? 0 : delta / maxVal

        if delta == 0 { h = 0 }
        else if maxVal == r { h = (g - b) / delta + (g < b ? 6 : 0) }
        else if maxVal == g { h = (b - r) / delta + 2 }
        else { h = (r - g) / delta + 4 }
        h /= 6

        return (h * 360, s * 100, v * 100)
    }

    // Convert RGB → CMYK
    private func rgbToCMYK(_ rgb: RGB) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let r = CGFloat(rgb.r) / 255
        let g = CGFloat(rgb.g) / 255
        let b = CGFloat(rgb.b) / 255

        let k = 1 - max(r, max(g, b))
        let c = (1 - r - k) / (1 - k)
        let m = (1 - g - k) / (1 - k)
        let y = (1 - b - k) / (1 - k)
        return (c * 100, m * 100, y * 100, k * 100)
    }
}

// MARK: - Subviews

private struct ValueRow: View {
    let label: String
    let value: String
    let color: Color
    @State private var copied = false

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).frame(width: 90, alignment: .leading)
            Spacer()
            Text(value)
                .fontWeight(.medium)
            Button {
                UIPasteboard.general.string = value
                withAnimation { copied = true }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundColor(copied ? .green : .gray)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ColorComponentRow: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).frame(width: 90, alignment: .leading)
            Spacer()
            Text("\(value)")
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

private struct CopyButton: View {
    let label: String
    let value: String
    @Binding var copiedText: String?

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            withAnimation {
                copiedText = label
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            VStack {
                Image(systemName: "doc.on.doc")
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(width: 80, height: 70)
            .background(Color.white.opacity(0.9))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
    }
}
