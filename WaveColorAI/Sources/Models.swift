import SwiftUI
import CoreImage
import AVFoundation
import Combine

struct RGB: Identifiable, Codable, Equatable { var id: String { hex }; let r:Int; let g:Int; let b:Int
    var hex:String { String(format:"#%02X%02X%02X", r,g,b) }
    var uiColor: UIColor { UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1) }
    var rgbText:String { "\(r), \(g), \(b)" }
    var cmykText:String {
        let rf=Double(r)/255, gf=Double(g)/255, bf=Double(b)/255
        let k = 1 - max(rf,gf,bf)
        if k >= 0.999 { return "0%, 0%, 0%, 100%" }
        let c = (1-rf-k)/(1-k), m = (1-gf-k)/(1-k), y = (1-bf-k)/(1-k)
        return "\(Int(c*100))%, \(Int(m*100))%, \(Int(y*100))%, \(Int(k*100))%"
    }
    func distance(to o:RGB)->Double {
        let dr=Double(r-o.r), dg=Double(g-o.g), db=Double(b-o.b)
        return sqrt(dr*dr+dg*dg+db*db)
    }
}
func hexToRGB(_ hex:String)->RGB {
    var h = hex.uppercased(); if h.hasPrefix("#"){h.removeFirst()}
    let r = Int(h.prefix(2), radix:16) ?? 0
    let g = Int(h.dropFirst(2).prefix(2), radix:16) ?? 0
    let b = Int(h.dropFirst(4).prefix(2), radix:16) ?? 0
    return RGB(r:r,g:g,b:b)
}

struct NamedColor: Codable, Identifiable { var id:String { name }; let name:String; let hex:String }
struct PaintColor: Codable, Identifiable { var id:String { brand+name }; let brand:String; let name:String; let hex:String }

final class Catalog: ObservableObject {
    @Published var names:[NamedColor] = []
    @Published var paints:[PaintColor] = []
    init(){
        if let url = Bundle.main.url(forResource:"NamedColors", withExtension:"json"),
           let d = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([NamedColor].self, from:d) { names = arr }
        if let url = Bundle.main.url(forResource:"Paints", withExtension:"json"),
           let d = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([PaintColor].self, from:d) { paints = arr }
    }
    func nearestName(to rgb:RGB)->NamedColor? {
        names.min{ hexToRGB($0.hex).distance(to: rgb) < hexToRGB($1.hex).distance(to: rgb) }
    }
    func nearestPaint(to rgb:RGB)->PaintColor? {
        paints.min{ hexToRGB($0.hex).distance(to: rgb) < hexToRGB($1.hex).distance(to: rgb) }
    }
}
