
import SwiftUI
import UIKit
import AVFoundation
import Combine

enum PaywallConfig {
    static let weeklyPrice      = "US$ 5.99"
    static let monthlyPrice     = "US$ 14.99"
    static let yearlyPrice      = "US$ 59.99"
    static let monthlyTrialDays = 3
    static let yearlyTrialDays  = 3
    static let show50OffBadge   = true
}

struct RGB: Identifiable, Equatable, Hashable {
    let id = UUID().uuidString
    let r: Int; let g: Int; let b: Int
    var uiColor: UIColor { UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1) }
    var hex: String { String(format:"#%02X%02X%02X", r,g,b) }
    var rgbText: String { "R \(r)  G \(g)  B \(b)" }
}

enum KMeans {
    static func palette(from image: UIImage, k: Int = 5) -> [RGB] {
        guard let cg = image.cgImage else { return [] }
        let w = min(220, cg.width), h = min(220, cg.height)
        guard let ctx = CGContext(data:nil, width:w, height:h, bitsPerComponent:8, bytesPerRow:w*4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x:0,y:0,width:w,height:h))
        guard let data = ctx.data else { return [] }
        let p = data.bindMemory(to: UInt8.self, capacity: w*h*4)

        var samples:[RGB] = []
        let step = max(1, min(w,h)/40)
        for y in stride(from:0, to:h, by:step) {
            for x in stride(from:0, to:w, by:step) {
                let i = (y*w + x) * 4
                let r = Int(p[i+2]), g = Int(p[i+1]), b = Int(p[i+0])
                samples.append(RGB(r:r,g:g,b:b))
            }
        }
        guard !samples.isEmpty else { return [] }

        var centroids = (0..<k).map { _ in samples[Int.random(in: 0..<samples.count)] }
        for _ in 0..<10 {
            var sums = Array(repeating:(r:0,g:0,b:0,n:0), count:k)
            for s in samples {
                var j = 0; var best = Double.greatestFiniteMagnitude
                for i in 0..<k {
                    let c = centroids[i]
                    let dr = Double(s.r-c.r), dg = Double(s.g-c.g), db = Double(s.b-c.b)
                    let d = dr*dr + dg*dg + db*db
                    if d < best { best = d; j = i }
                }
                sums[j].r += s.r; sums[j].g += s.g; sums[j].b += s.b; sums[j].n += 1
            }
            for i in 0..<k where sums[i].n > 0 {
                centroids[i] = RGB(r: sums[i].r/sums[i].n,
                                   g: sums[i].g/sums[i].n,
                                   b: sums[i].b/sums[i].n)
            }
        }
        var seen = Set<String>(); var uniq:[RGB] = []
        for c in centroids { if !seen.contains(c.hex) { seen.insert(c.hex); uniq.append(c) } }
        return uniq
    }
}

