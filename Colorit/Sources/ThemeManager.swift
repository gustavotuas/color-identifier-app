import SwiftUI
import Combine

// MARK: - Tema disponible
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "system".localized
        case .light: return "light".localized
        case .dark: return "dark".localized
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - ThemeManager (sin @AppStorage)
@MainActor
final class ThemeManager: ObservableObject {

    @Published var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "selectedTheme")
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = AppTheme(rawValue: saved) {
            self.selectedTheme = theme
        } else {
            self.selectedTheme = .system
        }
    }
}
