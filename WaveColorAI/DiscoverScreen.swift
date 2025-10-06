
import SwiftUI

struct DiscoverScreen: View {
    @State private var base = RGB(r: 64, g: 120, b: 220)
    @State private var suggested: [RGB] = []
    @State private var meaning = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    SwatchView(c: base)
                    VStack(alignment:.leading) {
                        Text(base.hex).font(.headline)
                        Text(base.rgbText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Randomize") { base = RGB(r: .random(in: 0...255), g: .random(in: 0...255), b: .random(in: 0...255)) }
                }
                .padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    suggested = Harmony.suggest(from: base)
                    meaning = ColorCoach.meaning(for: base)
                } label: {
                    Label("Suggest me a palette", systemImage: "paintbrush.pointed")
                }.buttonStyle(.borderedProminent)

                if !suggested.isEmpty {
                    Text("Suggested palette").frame(maxWidth:.infinity, alignment:.leading)
                    HStack { ForEach(Array(suggested.enumerated()), id: \.offset) { _, c in SwatchView(c: c) } }
                    if !meaning.isEmpty {
                        Text(meaning).font(.callout).foregroundStyle(.secondary)
                            .padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.padding()
        }.navigationTitle("Discover")
    }
}

enum Harmony {
    static func clamp(_ v:Int)->Int { max(0, min(255, v)) }
    static func complement(_ c: RGB) -> RGB { RGB(r:255-c.r, g:255-c.g, b:255-c.b) }
    static func triad(_ c: RGB) -> [RGB] { [RGB(r:c.g,g:c.b,b:c.r), RGB(r:c.b,g:c.r,b:c.g)] }
    static func analog(_ c: RGB) -> [RGB] {
        [RGB(r:clamp(c.r+30), g:clamp(c.g+15), b:clamp(c.b-15)),
         RGB(r:clamp(c.r-30), g:clamp(c.g-15), b:clamp(c.b+15))]
    }
    static func suggest(from c: RGB) -> [RGB] {
        var out = [c, complement(c)]
        out.append(contentsOf: triad(c)); out.append(contentsOf: analog(c))
        var seen = Set<String>(); var uniq:[RGB] = []
        for x in out where !seen.contains(x.hex) { uniq.append(x); seen.insert(x.hex) }
        return Array(uniq.prefix(5))
    }
}

enum ColorCoach {
    static func meaning(for c: RGB) -> String {
        let maxV = Double(max(c.r, max(c.g, c.b))) / 255.0
        let minV = Double(min(c.r, min(c.g, c.b))) / 255.0
        let s = maxV == 0 ? 0 : (maxV - minV) / maxV
        if s < 0.15 { return "Neutral colour: great for minimal and calm designs." }
        if c.r > c.g && c.r > c.b { return "Reddish tone: evokes energy, passion and attention." }
        if c.g > c.r && c.g > c.b { return "Greenish tone: evokes balance, growth and freshness." }
        if c.b > c.r && c.b > c.g { return "Bluish tone: evokes calm, trust and clarity." }
        return "Balanced tone: versatile for multiple contexts."
    }
}
