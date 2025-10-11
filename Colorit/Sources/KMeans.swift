import UIKit

enum KMeans {
    static func palette(from image: UIImage, k: Int = 5) -> [RGB] {
        guard let cg = image.cgImage else { return [] }

        let w = min(200, cg.width)
        let h = min(200, cg.height)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        ctx?.interpolationQuality = .low
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

        guard let data = ctx?.data else { return [] }
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        var samples: [RGB] = []
        let step = max(1, min(w, h) / 40)

        // Extrae píxeles de la imagen reducida
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                let i = (y * w + x) * 4
                let r = Int(p[i])
                let g = Int(p[i + 1])
                let b = Int(p[i + 2])
                samples.append(RGB(r: r, g: g, b: b))
            }
        }

        if samples.isEmpty { return [] }

        // Inicializa centroides
        var centroids: [RGB] = (0..<k).map { _ in samples[Int.random(in: 0..<samples.count)] }

        // Iteraciones K-Means
        for _ in 0..<10 {
            var sums = Array(repeating: (r: 0.0, g: 0.0, b: 0.0, n: 0.0), count: k)

            for s in samples {
                var j = 0
                var best = Double.greatestFiniteMagnitude
                for i in 0..<k {
                    let d = s.distance(to: centroids[i])
                    if d < best {
                        best = d
                        j = i
                    }
                }
                sums[j].r += Double(s.r)
                sums[j].g += Double(s.g)
                sums[j].b += Double(s.b)
                sums[j].n += 1
            }

            for i in 0..<k where sums[i].n > 0 {
                centroids[i] = RGB(
                    r: Int(sums[i].r / sums[i].n),
                    g: Int(sums[i].g / sums[i].n),
                    b: Int(sums[i].b / sums[i].n)
                )
            }
        }

        return centroids
    }
}
