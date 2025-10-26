import SwiftUI
import Combine
import Foundation

@MainActor
final class LanguageManager: ObservableObject {
    @AppStorage("selectedLanguage") var selectedLanguageCode: String = "system" {
        didSet {
            applyLanguage(selectedLanguageCode)
        }
    }

    private let systemLanguageCode: String

    init() {
        // Guarda el idioma real con el que arrancó el teléfono
        self.systemLanguageCode = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"
        applyLanguage(selectedLanguageCode)
    }

    func applyLanguage(_ code: String) {
        let targetCode: String

        if code == "system" {
            // ✅ Siempre regresa al idioma con el que arrancó el teléfono
            targetCode = systemLanguageCode
        } else {
            targetCode = code
        }

        Bundle.setLanguage(targetCode)
        objectWillChange.send()
    }
}
