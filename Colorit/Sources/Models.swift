import SwiftUI
import Combine

// MARK: - RGB MODEL
struct RGB: Identifiable, Codable, Equatable {
    var id = UUID()
    var r: Int
    var g: Int
    var b: Int

    var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbText: String {
        "RGB(\(r), \(g), \(b))"
    }

    var cmykText: String {
        let rf = Double(r) / 255
        let gf = Double(g) / 255
        let bf = Double(b) / 255
        let k = 1 - max(rf, max(gf, bf))
        if k == 1 { return "C:0%, M:0%, Y:0%, K:100%" }
        let c = (1 - rf - k) / (1 - k)
        let m = (1 - gf - k) / (1 - k)
        let y = (1 - bf - k) / (1 - k)
        return String(format: "C:%d%%, M:%d%%, Y:%d%%, K:%d%%",
                      Int(c * 100), Int(m * 100), Int(y * 100), Int(k * 100))
    }

    func distance(to other: RGB) -> Double {
        let dr = Double(r - other.r)
        let dg = Double(g - other.g)
        let db = Double(b - other.b)
        return sqrt(dr * dr + dg * dg + db * db)
    }
}

// MARK: - HEX → RGB HELPER
func hexToRGB(_ hex: String) -> RGB {
    var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    if h.count == 3 {
        h = h.map { "\($0)\($0)" }.joined()
    }
    let scanner = Scanner(string: h)
    var hexNumber: UInt64 = 0
    scanner.scanHexInt64(&hexNumber)

    let r = Int((hexNumber & 0xFF0000) >> 16)
    let g = Int((hexNumber & 0x00FF00) >> 8)
    let b = Int(hexNumber & 0x0000FF)
    return RGB(r: r, g: g, b: b)
}

extension RGB {
    var uiColor: UIColor {
        UIColor(red: CGFloat(r) / 255,
                 green: CGFloat(g) / 255,
                 blue: CGFloat(b) / 255,
                 alpha: 1)
    }
}

// MARK: - NamedColor MODEL
// struct NamedColor: Identifiable, Codable, Hashable {
//     var id: String { hex }
//     let name: String
//     let hex: String
//     let rgb: String?
//     let group: String?
//     let theme: String?
//     let brand: String?
//     let line: String?
//     let code: String?
// }

// MARK: - PaintColor MODEL
struct PaintColor: Codable, Identifiable {
    var id: String { brand + name }
    let brand: String
    let name: String
    let hex: String
}

// MARK: - Catalog STORE
@MainActor
final class Catalog: ObservableObject {
    @Published var names: [NamedColor] = []
    @Published var paints: [PaintColor] = []

    init() {
        load()
    }

    func load() {
        var combined: [NamedColor] = []

        // Load ColorsExtended.json
        if let url = Bundle.main.url(forResource: "ColorsExtended", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([NamedColor].self, from: data)
                combined.append(contentsOf: decoded)
                print("✅ Loaded \(decoded.count) colors from ColorsExtended.json")
            } catch {
                print("❌ Error decoding ColorsExtended.json:", error)
            }
        }

        // Load NamedColors.json (optional merge)
        if let url = Bundle.main.url(forResource: "NamedColors", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([NamedColor].self, from: data)
                combined.append(contentsOf: decoded)
                print("✅ Loaded \(decoded.count) base colors from NamedColors.json")
            } catch {
                print("⚠️ Could not decode NamedColors.json:", error)
            }
        }

        // Deduplicate by hex
        let unique = Dictionary(grouping: combined, by: \.hex).compactMapValues { $0.first }
        self.names = Array(unique.values).sorted(by: { $0.name < $1.name })

        // Load Paints.json if exists
        if let url = Bundle.main.url(forResource: "Paints", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                self.paints = try JSONDecoder().decode([PaintColor].self, from: data)
                print("✅ Loaded \(paints.count) paints.")
            } catch {
                print("⚠️ Could not decode Paints.json:", error)
            }
        }

        print("🎨 Catalog loaded: \(names.count) colors, \(paints.count) paints.")
    }
}

// MARK: - Color Matching Helpers
extension Catalog {

    /// Encuentra el color más parecido en la lista de colores `names`
    func nearestName(to rgb: RGB) -> NamedColor? {
        guard !names.isEmpty else { return nil }

        var nearest: NamedColor?
        var minDistance = Double.greatestFiniteMagnitude

        for c in names {
            let rgb2 = hexToRGB(c.hex)
            let dist = rgb.distance(to: rgb2)
            if dist < minDistance {
                minDistance = dist
                nearest = c
            }
        }
        return nearest
    }

    /// Encuentra la pintura más parecida al color capturado (si tienes Paints.json)
    func nearestPaint(to rgb: RGB) -> PaintColor? {
        guard !paints.isEmpty else { return nil }

        var nearest: PaintColor?
        var minDistance = Double.greatestFiniteMagnitude

        for p in paints {
            let rgb2 = hexToRGB(p.hex)
            let dist = rgb.distance(to: rgb2)
            if dist < minDistance {
                minDistance = dist
                nearest = p
            }
        }
        return nearest
    }
}
