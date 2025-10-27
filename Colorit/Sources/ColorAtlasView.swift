import SwiftUI

// MARK: - Helpers

@inline(__always)
private func normalizeHex(_ hex: String) -> String {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    return s
}

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

// MARK: - Types

enum AtlasMode: String, CaseIterable {
    case hueLightness = "Lightness"
    case hueSaturation = "Saturation"
}

struct BucketKey: Hashable, Identifiable {
    let hIdx: Int
    let yIdx: Int
    var id: String { "\(hIdx)-\(yIdx)" }
}

struct BucketData {
    var count: Int = 0
    var representative: NamedColor?
}

// MARK: - Main View

struct ColorAtlasView: View {
    @EnvironmentObject var favs: FavoritesStore
    let colors: [NamedColor]

    @State private var hueBins: Int = 6
    @State private var mode: AtlasMode = .hueLightness
    @State private var baseYBins: Int = 14
    @State private var showing: BucketKey?

    var body: some View {
        VStack(spacing: 10) {

            // Picker (Lightness / Saturation)
            HStack {
                Picker("", selection: $mode) {
                    ForEach(AtlasMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 6)

            // Atlas grid
            BucketGrid(
                colors: colors,
                mode: mode,
                hueBins: hueBins,
                baseYBins: baseYBins
            ) { key in
                showing = key
            }
        }
        .sheet(item: $showing) { key in
            BucketDetailSheet(
                key: key,
                colors: colors,
                mode: mode,
                hueBins: hueBins,
                baseYBins: baseYBins
            )
            .environmentObject(favs)
        }
    }
}

// MARK: - Grid with dynamic rows

private struct BucketGrid: View {
    @EnvironmentObject var favs: FavoritesStore
    let colors: [NamedColor]
    let mode: AtlasMode
    let hueBins: Int
    let baseYBins: Int
    let onTapBucket: (BucketKey) -> Void

    private func buildBuckets() -> (buckets: [BucketKey: BucketData], yMin: Int, yMax: Int) {
        var dict: [BucketKey: BucketData] = [:]
        var yMin = Int.max
        var yMax = Int.min

        for c in colors {
            let rgb = hexToRGB(c.hex)
            let (h, s, l) = rgbToHSL(rgb)
            let hIdx = max(0, min(hueBins - 1, Int((h / 360.0) * Double(hueBins))))
            let yRaw = (mode == .hueLightness) ? l : s
            let yIdx = max(0, min(baseYBins - 1, Int(yRaw * Double(baseYBins))))

            let key = BucketKey(hIdx: hIdx, yIdx: yIdx)
            var data = dict[key] ?? BucketData()
            data.count += 1
            if data.representative == nil { data.representative = c }
            dict[key] = data

            yMin = min(yMin, yIdx)
            yMax = max(yMax, yIdx)
        }

        if dict.isEmpty {
            yMin = 0; yMax = 0
        }
        return (dict, yMin, yMax)
    }

    var body: some View {
        GeometryReader { geo in
            let (buckets, yMin, yMax) = buildBuckets()
            let spacing: CGFloat = 6
            let width = geo.size.width - 24 // 12 padding each side
            let cellW = (width - spacing * CGFloat(hueBins - 1)) / CGFloat(hueBins)
            let rowsCount = max(1, (yMax - yMin + 1))
            let totalHeight = CGFloat(rowsCount) * cellW + spacing * CGFloat(rowsCount - 1)

            ScrollView {
                VStack(spacing: spacing) {
                    ForEach((yMin...yMax).reversed(), id: \.self) { y in
                        HStack(spacing: spacing) {
                            ForEach(0..<hueBins, id: \.self) { h in
                                let key = BucketKey(hIdx: h, yIdx: y)
                                let data = buckets[key]
                                BucketCell(
                                    data: data,
                                    key: key,
                                    favs: favs,
                                    onTapBucket: onTapBucket
                                )
                                .frame(width: cellW, height: cellW)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(width: geo.size.width)
                .frame(height: totalHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Bucket Cell (clean look, double tap like)

private struct BucketCell: View {
    let data: BucketData?
    let key: BucketKey
    @ObservedObject var favs: FavoritesStore
    let onTapBucket: (BucketKey) -> Void

    private var isFav: Bool {
        guard let hex = data?.representative?.hex else { return false }
        let key = normalizeHex(hex)
        return favs.colors.contains { normalizeHex($0.color.hex) == key }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                Group {
                    if let rep = data?.representative {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hexToRGB(rep.hex).uiColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    }
                }
            )
            .overlay(
                Group {
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
            )
            .opacity((data?.count ?? 0) == 0 ? 0.35 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { toggleFav() }
            .onTapGesture(count: 1) { onTapBucket(key) }
    }

    private func toggleFav() {
        guard let rep = data?.representative else { return }
        let rgb = hexToRGB(rep.hex)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if isFav {
                favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            } else {
                let exists = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
                if !exists { favs.add(color: rgb) }
            }
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

// MARK: - Bucket Detail Sheet (tap color → opens ColorDetailView)

private struct BucketDetailSheet: View {
    let key: BucketKey
    let colors: [NamedColor]
    let mode: AtlasMode
    let hueBins: Int
    let baseYBins: Int

    @EnvironmentObject var favs: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    @State private var pageSize = 80
    private let pageStep = 80

    // 👇 nuevo estado para abrir ColorDetailView
    @State private var selectedColor: NamedColor? = nil

    private var itemsAll: [NamedColor] {
        let filtered = colors.filter { c in
            let rgb = hexToRGB(c.hex)
            let (h, s, l) = rgbToHSL(rgb)
            let hIdx = max(0, min(hueBins - 1, Int((h / 360.0) * Double(hueBins))))
            let yRaw = (mode == .hueLightness) ? l : s
            let yIdx = max(0, min(baseYBins - 1, Int(yRaw * Double(baseYBins))))
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
                        BucketRowItem(nc: nc, onTap: { selectedColor = nc })
                            .environmentObject(favs)
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
        }
        // 👇 sheet para abrir ColorDetailView al tocar el color
        .sheet(item: $selectedColor) { color in
            ColorDetailView(color: color)
                .environmentObject(favs)
        }
    }
}

private struct BucketRowItem: View {
    @EnvironmentObject var favs: FavoritesStore
    let nc: NamedColor
    let onTap: () -> Void
    @State private var animateFav = false

    private var isFav: Bool {
        let key = normalizeHex(nc.hex)
        return favs.colors.contains { normalizeHex($0.color.hex) == key }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Swatch SIN gestos (para no competir con los del row)
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

            LikeFavoriteSmallButton(hex: nc.hex)
                .scaleEffect(animateFav ? 1.12 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: animateFav)
        }
        .padding(.vertical, 2)
        // El row entero define la zona táctil
        .contentShape(Rectangle())
        // 1) Doble tap con prioridad alta -> like/unlike
        .highPriorityGesture(
            TapGesture(count: 2).onEnded { toggleFav() }
        )
        // 2) Tap simple -> abrir ColorDetailView
        .onTapGesture {
            onTap()
        }
    }

    private func toggleFav() {
        let rgb = hexToRGB(nc.hex)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if isFav {
                favs.colors.removeAll { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
            } else {
                let exists = favs.colors.contains { normalizeHex($0.color.hex) == normalizeHex(rgb.hex) }
                if !exists { favs.add(color: rgb) }
            }
            animateFav.toggle()
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}



