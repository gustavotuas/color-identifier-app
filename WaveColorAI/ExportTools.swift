
import UIKit
import SwiftUI
import PDFKit

enum ExportTools {
    static func exportPalettePDF(_ colors: [RGB]) -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Palette.pdf")
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url, withActions: { ctx in
                ctx.beginPage()
                let title = "WaveColorAI Palette"
                (title as NSString).draw(at: CGPoint(x:40,y:40), withAttributes: [.font:UIFont.boldSystemFont(ofSize:22)])

                var x: CGFloat = 40; var y: CGFloat = 100
                for c in colors {
                    c.uiColor.setFill()
                    UIBezierPath(roundedRect: CGRect(x:x,y:y,width:120,height:120), cornerRadius:12).fill()
                    let info = "\(c.hex)   \(c.rgbText)"
                    (info as NSString).draw(at: CGPoint(x:x, y:y+130), withAttributes: [.font:UIFont.systemFont(ofSize:12)])
                    x += 140; if x > 480 { x = 40; y += 170 }
                }
            })
            return url
        } catch {
            print("PDF export error:", error)
            return nil
        }
    }
}

enum ShareSheet {
    static func present(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        root.present(vc, animated: true)
    }
}

extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: { $0.isKeyWindow }) }
}
