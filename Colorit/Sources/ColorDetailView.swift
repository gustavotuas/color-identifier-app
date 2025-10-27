import SwiftUI
import UIKit

// Normaliza HEX: quita espacios, "#", y lo pone en UPPERCASE.
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

struct ColorDetailView: View {
    @EnvironmentObject var favs: FavoritesStore
    let color: NamedColor

    @State private var selectedTab = "RGB"
    @State private var copiedText: String? = nil
    @State private var showCopyAlert = false
    @State private var isFavorite = false
    @State private var heartPulse = false

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

                    // ✅ Reemplazo del heart por LikeFavoriteSmallButton
                    LikeFavoriteSmallButton(hex: color.hex)
                        .environmentObject(favs)
                }
                .padding(.top, 8)

                // MARK: - Tabs
                Picker("Mode", selection: $selectedTab) {
                    ForEach(tabs, id: \.self) { tab in
                        Text(tab).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: selectedTab) { _ in
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }

                // MARK: - Tab content
                VStack(spacing: 12) {
                    switch selectedTab {
                    case "RGB":
                        ValueRow(label: "Red", value: "\(rgb.r)", color: .red)
                        ValueRow(label: "Green", value: "\(rgb.g)", color: .green)
                        ValueRow(label: "Blue", value: "\(rgb.b)", color: .blue)

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

                // MARK: - Vendor Info
                if let v = color.vendor {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vendor").font(.headline)
                        if let brand = v.brand, !brand.isEmpty {
                            InfoRow(label: "Brand", value: brand)
                        }
                        if let code = v.code, !code.isEmpty {
                            HStack(spacing: 8) {
                                InfoRow(label: "Code", value: code)
                                Button {
                                    UIPasteboard.general.string = code
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        if let locator = v.locator, !locator.isEmpty, locator.uppercased() != "N/A" {
                            InfoRow(label: "Locator", value: locator)
                        }
                        if let line = v.line, !line.isEmpty {
                            InfoRow(label: "Line", value: line)
                        }
                        if let domain = v.domain, !domain.isEmpty {
                            InfoRow(label: "Domain", value: domain)
                        }
                        if let source = v.source, !source.isEmpty {
                            InfoRow(label: "Source", value: source)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                    .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
            .padding(.bottom, 60)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            isFavorite = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(color.hex) }
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

    // MARK: - Favorite toggle
    private func toggleFavorite() {
        let rgb = hexToRGB(color.hex)
        if isFavorite {
            favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            isFavorite = false
        } else {
            let exists = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            if !exists { favs.add(color: rgb) }
            isFavorite = true
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        heartPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { heartPulse = false }
    }
}

// MARK: - Helpers
private func rgbToHSB(_ rgb: RGB) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
    UIColor(red: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
        .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
    return (hue * 360, saturation * 100, brightness * 100)
}

private func rgbToCMYK(_ rgb: RGB) -> (c: CGFloat, m: CGFloat, y: CGFloat, k: CGFloat) {
    let r = CGFloat(rgb.r) / 255, g = CGFloat(rgb.g) / 255, b = CGFloat(rgb.b) / 255
    let k = 1 - max(r, max(g, b))
    if k == 1 { return (0, 0, 0, 100) }
    let c = (1 - r - k) / (1 - k)
    let m = (1 - g - k) / (1 - k)
    let y = (1 - b - k) / (1 - k)
    return (c * 100, m * 100, y * 100, k * 100)
}

// MARK: - Subviews
private struct ValueRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.body.monospaced())
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline.weight(.medium))
            Spacer()
            Text(value).font(.subheadline)
        }
    }
}

private struct CopyButton: View {
    let label: String
    let value: String
    @Binding var copiedText: String?

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copiedText = label
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            Label(label, systemImage: "doc.on.doc")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: Capsule())
        }
    }
}
