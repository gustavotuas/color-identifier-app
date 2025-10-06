import SwiftUI

enum AIKit {
    static func smartPalette(from base: RGB) -> [RGB] {
        // Simple harmonic palette stub (complementary + triadic)
        let r = base.r, g = base.g, b = base.b
        let comp = RGB(r:255-r, g:255-g, b:255-b)
        let tri1 = RGB(r:b, g:r, b:g)
        let tri2 = RGB(r:g, g:b, b:r)
        return [base, comp, tri1, tri2, RGB(r:(r+comp.r)/2, g:(g+comp.g)/2, b:(b+comp.b)/2)]
    }
    static func colorCoach(for color: RGB) -> String {
        // Minimal offline hints
        if color.b > color.r && color.b > color.g { return "Calming and focused. Great for productivity and tech." }
        if color.r > color.g && color.r > color.b { return "Energetic and bold. Use for calls-to-action and passion." }
        if color.g > color.r && color.g > color.b { return "Natural and balanced. Ideal for wellness and growth." }
        return "Neutral and versatile. Good for backgrounds and modern UIs."
    }
}
