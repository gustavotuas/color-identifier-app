import SwiftUI

// MARK: - Helpers (locales a este archivo)

/// Normaliza HEX: quita espacios, "#", y lo pone en UPPERCASE.
@inline(__always)
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

/// Convierte RGB -> HSL. Usa tu `hexToRGB` existente fuera de este archivo.
private func rgbToHSL(_ rgb: RGB) -> (h: Double, s: Double, l: Double) {
    let r = Double(rgb.r) / 255.0
    let g = Double(rgb.g) / 255.0
    let b = Double(rgb.b) / 255.0

    let maxV = max(r,g,b), minV = min(r,g,b)
    let delta = maxV - minV

    var h = 0.0
    if delta != 0 {
        if maxV == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxV == g { h = ((b - r) / delta) + 2 }
        else { h = ((r - g) / delta) + 4 }
        h *= 60
        if h < 0 { h += 360 }
    }
    let l = (maxV + minV) / 2.0
    let s = delta == 0 ? 0 : delta / (1 - abs(2*l - 1))
    return (h, s, l)
}

// MARK: - Tipos del Atlas

/// Eje Y: usar Lightness o Saturation
enum AtlasMode: String, CaseIterable {
    case hueLightness = "Lightness"
    case hueSaturation = "Saturation"
}

/// Clave de bucket (cuadrícula)
struct BucketKey: Hashable, Identifiable {
    let hIdx: Int
    let yIdx: Int
    var id: String { "\(hIdx)-\(yIdx)" }
}

/// Datos por bucket
struct BucketData {
    var count: Int = 0
    var representative: NamedColor?
}

// MARK: - Vista principal

struct ColorAtlasView: View {
    let colors: [NamedColor]

    // ✅ Arranca con el mínimo de agrupaciones para mejor visibilidad
    @State private var mode: AtlasMode = .hueLightness
    @State private var hueBins: Int = 6   // mínimo
    @State private var yBins: Int = 5     // mínimo

    @State private var showing: BucketKey?
    @State private var bucketsCache: [BucketKey: BucketData] = [:]

    var body: some View {
        VStack(spacing: 12) {

            // Controles compactos (solo modo, sin steppers)
            HStack {
                Picker("", selection: $mode) {
                    ForEach(AtlasMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            // Cuadrícula compacta (siempre cuadrado)
            BucketGrid(
                colors: colors,
                mode: mode,
                hueBins: hueBins,
                yBins: yBins
            ) { key in
                showing = key
            }
            .onChange(of: colors) { _ in bucketsCache.removeAll() }
            .onChange(of: mode) { _ in bucketsCache.removeAll() }
        }
        .sheet(item: $showing) { key in
            BucketDetailSheet(
                key: key,
                colors: colors,
                mode: mode,
                hueBins: hueBins,
                yBins: yBins
            )
        }
    }
}

// MARK: - Grid compacto

private struct BucketGrid: View {
    let colors: [NamedColor]
    let mode: AtlasMode
    let hueBins: Int
    let yBins: Int
    let onTapBucket: (BucketKey) -> Void

    private var buckets: [BucketKey: BucketData] {
        var dict: [BucketKey: BucketData] = [:]
        for c in colors {
            let rgb = hexToRGB(c.hex)
            let (h, s, l) = rgbToHSL(rgb)

            let hIdx = max(0, min(hueBins - 1, Int((h / 360.0) * Double(hueBins))))
            let yRaw = (mode == .hueLightness) ? l : s
            let yIdx = max(0, min(yBins - 1, Int(yRaw * Double(yBins))))

            let key = BucketKey(hIdx: hIdx, yIdx: yIdx)
            var data = dict[key] ?? BucketData()
            data.count += 1
            if data.representative == nil { data.representative = c }
            dict[key] = data
        }
        return dict
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let spacing: CGFloat = 6
            let cell = (side - spacing * CGFloat(hueBins - 1)) / CGFloat(hueBins)

            VStack(spacing: spacing) {
                ForEach((0..<yBins).reversed(), id: \.self) { y in
                    HStack(spacing: spacing) {
                        ForEach(0..<hueBins, id: \.self) { h in
                            let key = BucketKey(hIdx: h, yIdx: y)
                            let data = buckets[key]
                            BucketCell(data: data) { onTapBucket(key) }
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width/2, y: geo.size.height/2)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal)
    }
}

// MARK: - Bucket cell

private struct BucketCell: View {
    let data: BucketData?
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))

                if let rep = data?.representative {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hexToRGB(rep.hex).uiColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        )
                }

                if let count = data?.count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 5)
                        .background(Color.black.opacity(0.35), in: Capsule())
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .opacity((data?.count ?? 0) == 0 ? 0.35 : 1.0)
    }
}

// MARK: - Detalle con paginación

private struct BucketDetailSheet: View {
    let key: BucketKey
    let colors: [NamedColor]
    let mode: AtlasMode
    let hueBins: Int
    let yBins: Int

    @Environment(\.dismiss) private var dismiss

    @State private var pageSize = 60
    private let pageStep = 60

    private var itemsAll: [NamedColor] {
        let filtered = colors.filter { c in
            let rgb = hexToRGB(c.hex)
            let (h, s, l) = rgbToHSL(rgb)
            let hIdx = max(0, min(hueBins - 1, Int((h / 360.0) * Double(hueBins))))
            let yRaw = (mode == .hueLightness) ? l : s
            let yIdx = max(0, min(yBins - 1, Int(yRaw * Double(yBins))))
            return hIdx == key.hIdx && yIdx == key.yIdx
        }
        return filtered.sorted {
            let ka = "\($0.name)|\($0.vendor?.code ?? "")|\($0.hex.lowercased())"
            let kb = "\($1.name)|\($1.vendor?.code ?? "")|\($1.hex.lowercased())"
            return ka < kb
        }
    }

    private var itemsPage: ArraySlice<NamedColor> { itemsAll.prefix(pageSize) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(itemsPage) { nc in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hexToRGB(nc.hex).uiColor))
                                .frame(width: 42, height: 42)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(nc.name).font(.subheadline).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(nc.hex).font(.caption).foregroundColor(.secondary)
                                    if let brand = nc.vendor?.brand, let code = nc.vendor?.code {
                                        Text("• \(brand) \(code)")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            FavoriteToggleButton(hex: nc.hex)
                        }
                    }

                    if itemsAll.count > pageSize {
                        Button {
                            withAnimation(.easeInOut) { pageSize += pageStep }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Show more (\(min(pageStep, itemsAll.count - pageSize)))")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Colors \(min(pageSize, itemsAll.count))/\(itemsAll.count)")
                }
            }
            .navigationTitle("Bucket \(key.hIdx + 1) · \(key.yIdx + 1)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
    }
}

// MARK: - Favorite toggle reutilizable

private struct FavoriteToggleButton: View {
    @EnvironmentObject var favs: FavoritesStore
    let hex: String

    private var isFav: Bool {
        let key = normalizeHex(hex)
        return favs.colors.contains { normalizeHex($0.color.hex) == key }
    }

    var body: some View {
        Button {
            let rgb = hexToRGB(hex)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                if isFav {
                    favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
                } else {
                    let exists = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
                    if !exists { favs.add(color: rgb) }
                }
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Image(systemName: isFav ? "heart.fill" : "heart")
                .foregroundColor(isFav ? .pink : .gray)
        }
        .buttonStyle(.plain)
    }
}
