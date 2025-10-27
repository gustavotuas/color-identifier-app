import SwiftUI
import UIKit

// MARK: - Normalize HEX
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

struct ColorDetailView: View {
    @EnvironmentObject var favs: FavoritesStore
    @Environment(\.dismiss) private var dismiss
    let color: NamedColor

    @State private var selectedTab = "RGB"
    @State private var toastMessage: String? = nil
    @State private var isFavorite = false
    @State private var animateLike = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    private var rgb: RGB { hexToRGB(color.hex) }
    private let tabs = ["RGB", "HEX", "HSB", "CMYK"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // MARK: - Color Preview
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(rgb.uiColor))
                        .frame(height: 200)
                        .overlay(
                            VStack(spacing: 4) {
                                Text(color.name)
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                                Text(color.hex)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(
                                Color.black.opacity(0.45),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                        .padding(.horizontal)

                    // MARK: - Copy + Share + Like
                    HStack(spacing: 22) {
                        Button {
                            copyCurrentValue()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }

                        Button {
                            shareCurrentValue()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }

                        Button {
                            toggleFavorite()
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(isFavorite ? Color.clear : Color.gray.opacity(0.6), lineWidth: 1.4)
                                    .background(
                                        Circle()
                                            .fill(isFavorite ? Color(red: 30/255, green: 215/255, blue: 96/255) : Color.clear)
                                    )
                                    .frame(width: 20, height: 20)

                                Image(systemName: isFavorite ? "checkmark" : "plus")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(isFavorite ? .black : Color.gray.opacity(0.7))
                            }
                            .scaleEffect(animateLike ? 1.15 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: animateLike)
                        }
                        .buttonStyle(.plain)
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
                                InfoRow(label: "Code", value: code)
                            }
                            if let locator = v.locator, !locator.isEmpty, locator.uppercased() != "N/A" {
                                InfoRow(label: "Locator", value: locator)
                            }
                            if let line = v.line, !line.isEmpty {
                                InfoRow(label: "Line", value: line)
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Close").font(.subheadline.bold())
                        }
                    }
                    .tint(.secondary)
                }
            }

            // MARK: - Toast overlay
            .overlay(alignment: .bottom) {
                if let message = toastMessage {
                    Text(message)
                        .font(.caption.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(14)
                        .shadow(radius: 4)
                        .padding(.bottom, 40)
                        .transition(.opacity.combined(with: .scale))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { toastMessage = nil }
                            }
                        }
                }
            }
            // MARK: - iOS Share Sheet
            .sheet(isPresented: $showShareSheet) {
                if !shareItems.isEmpty {
                    ActivityViewController(items: shareItems)
                }
            }
        }
        .onAppear {
            isFavorite = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(color.hex) }
        }
    }

    // MARK: - Actions
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = text
        }
    }

    private func copyCurrentValue() {
        let text = currentValueString()
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showToast("Copied to clipboard")
    }

    private func shareCurrentValue() {
        let text = """
        🎨 \(color.name)
        HEX: \(color.hex)
        RGB: \(rgb.r), \(rgb.g), \(rgb.b)
        """

        let image = generateColorCard()
        shareItems = [text, image]
        showShareSheet = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showToast("Share sheet opened")
    }

    private func toggleFavorite() {
        let rgbValue = hexToRGB(color.hex)
        if isFavorite {
            favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgbValue.hex) }
            isFavorite = false
            showToast("Removed from collections")
        } else {
            if !favs.colors.contains(where: { normalizeHex($0.color.hex) == normalizeHex(rgbValue.hex) }) {
                favs.add(color: rgbValue)
            }
            isFavorite = true
            showToast("Added to collections")
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        animateLike.toggle()
    }

    // MARK: - Share Card (watermark auto contrast)
    private func generateColorCard() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
        let isProUser = false // ⬅️ Cambia según tu lógica real

        return renderer.image { ctx in
            let uiColor = rgb.uiColor
            uiColor.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600))

            let textColor: UIColor = uiColor.isLight ? .black : .white
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]

            let infoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: textColor.withAlphaComponent(0.9),
                .paragraphStyle: paragraphStyle
            ]

            // 🎨 Info principal
            (color.name as NSString).draw(in: CGRect(x: 0, y: 200, width: 600, height: 50), withAttributes: titleAttrs)
            ("HEX: \(color.hex)" as NSString).draw(in: CGRect(x: 0, y: 260, width: 600, height: 40), withAttributes: infoAttrs)
            ("RGB: \(rgb.r), \(rgb.g), \(rgb.b)" as NSString).draw(in: CGRect(x: 0, y: 310, width: 600, height: 40), withAttributes: infoAttrs)

            // 🪄 Marca de agua con contraste automático
            if !isProUser {
                let watermarkColor: UIColor = uiColor.isLight ? .black.withAlphaComponent(0.35) : .white.withAlphaComponent(0.4)

                if let logo = UIImage(named: "AppIcon") {
                    let logoSize: CGFloat = 70
                    let logoRect = CGRect(x: (600 - logoSize)/2, y: 470, width: logoSize, height: logoSize)
                    logo.withTintColor(watermarkColor, renderingMode: .alwaysOriginal).draw(in: logoRect, blendMode: .normal, alpha: 0.9)
                }

                let watermarkAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 28),
                    .foregroundColor: watermarkColor,
                    .paragraphStyle: paragraphStyle
                ]
                ("Colorit" as NSString).draw(in: CGRect(x: 0, y: 545, width: 600, height: 40), withAttributes: watermarkAttrs)
            }
        }
    }

    private func currentValueString() -> String {
        switch selectedTab {
        case "RGB":
            return "RGB: \(rgb.r), \(rgb.g), \(rgb.b)"
        case "HEX":
            return "HEX: \(color.hex)"
        case "HSB":
            let (h, s, b) = rgbToHSB(rgb)
            return "HSB: \(Int(h))°, \(Int(s))%, \(Int(b))%"
        case "CMYK":
            let (c, m, y, k) = rgbToCMYK(rgb)
            return "CMYK: \(Int(c))%, \(Int(m))%, \(Int(y))%, \(Int(k))%"
        default:
            return color.hex
        }
    }
}

// MARK: - UIKit Integration for Share Sheet
struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Helpers
private func rgbToHSB(_ rgb: RGB) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
    var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
    UIColor(red: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
        .getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
    return (hue * 360, sat * 100, bri * 100)
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

private extension UIColor {
    var isLight: Bool {
        var white: CGFloat = 0
        getWhite(&white, alpha: nil)
        return white > 0.6
    }
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
