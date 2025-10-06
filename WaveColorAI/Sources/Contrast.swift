import SwiftUI

func wcagContrast(_ a: RGB, _ b: RGB) -> Double {
    func srgbToLinear(_ x: Double) -> Double {
        return (x <= 0.04045) ? (x/12.92) : pow((x + 0.055)/1.055, 2.4)
    }
    func luminance(_ c: RGB) -> Double {
        let R = srgbToLinear(Double(c.r)/255.0)
        let G = srgbToLinear(Double(c.g)/255.0)
        let B = srgbToLinear(Double(c.b)/255.0)
        return 0.2126*R + 0.7152*G + 0.0722*B
    }
    let L1 = luminance(a)
    let L2 = luminance(b)
    let hi = max(L1, L2)
    let lo = min(L1, L2)
    return (hi + 0.05) / (lo + 0.05)
}

struct ContrastTool: View {
    @State private var c1 = RGB(r: 0, g: 0, b: 0)
    @State private var c2 = RGB(r: 255, g: 255, b: 255)
    var ratio: Double { wcagContrast(c1, c2) }
    var body: some View {
        Form {
            Section("Colors") {
                HStack {
                    VStack {
                        ColorPicker("A", selection: .constant(Color(c1.uiColor)))
                        Text(c1.hex)
                    }
                    VStack {
                        ColorPicker("B", selection: .constant(Color(c2.uiColor)))
                        Text(c2.hex)
                    }
                }
            }
            Section("Contrast") {
                Text(String(format: "Ratio: %.2f:1", ratio))
                Text(ratio >= 4.5 ? "Pass (AA body)" : "Fail (AA body)").foregroundColor(ratio >= 4.5 ? .green : .red)
            }
        }
        .navigationTitle(NSLocalizedString("contrast", comment: ""))
    }
}