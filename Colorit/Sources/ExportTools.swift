import SwiftUI
import PDFKit

enum ExportTools {
    static func exportPalettePDF(_ colors: [RGB]) -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Palette.pdf")
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        
        do {
            try pdf.writePDF(to: url, withActions: { ctx in
                ctx.beginPage()
                
                let title = "Colorit Palette"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 24)
                ]
                title.draw(at: CGPoint(x: 40, y: 40), withAttributes: attrs)
                
                var x: CGFloat = 40
                var y: CGFloat = 100
                
                for c in colors {
                    let fillColor = UIColor(red: CGFloat(c.r)/255, green: CGFloat(c.g)/255, blue: CGFloat(c.b)/255, alpha: 1)
                    fillColor.setFill()
                    
                    let rect = CGRect(x: x, y: y, width: 120, height: 120)
                    UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
                    
                    let hex = c.hex as NSString
                    hex.draw(at: CGPoint(x: x, y: y + 130), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 12)
                    ])
                    
                    x += 140
                    if x > 480 {
                        x = 40
                        y += 170
                    }
                }
            })
            
            return url
        } catch {
            print("PDF export error:", error)
            return nil
        }
    }
}
