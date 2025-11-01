import SwiftUI
import UIKit

// MARK: - Helper para Haptic Feedback
final class Haptic {
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - Pestañas principales
struct MainTabs: View {
    @EnvironmentObject var favs: FavoritesStore  // 👈 ahora sí tienes acceso al store
    @EnvironmentObject var store: StoreVM
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // 🔍 Search
            NavigationStack {
                SearchScreen()
            }
            .tabItem {
                Label("tab_search".localized, systemImage: "magnifyingglass")
            }
            .tag(0)

            // ❤️ Favorites
            NavigationStack {
                FavoritesScreen()
                    .environmentObject(favs)
                    .onAppear { favs.hasNewFavorites = false } // 👈 limpia el badge al entrar
            }
            .tabItem {
                Label("tab_collections".localized, systemImage: "rectangle.stack.fill")
            }
            .badge(favs.hasNewFavorites ? "●" : nil) // 👈 muestra el puntito de novedades
            .tag(1)

            // 📷 Camera
            NavigationStack {
                CameraScreen()
            }
            .tabItem {
                Label("tab_camera".localized, systemImage: "camera")
            }
            .tag(2)

            // 🖼 Photos
            NavigationStack {
                PhotosScreen()
            }
            .tabItem {
                Label("tab_photos".localized, systemImage: "photo")
            }
            .tag(3)

            // ⚙️ Settings
            NavigationStack {
                SettingScreen()
            }
            .tabItem {
                Label("tab_settings".localized, systemImage: "gearshape")
            }
            .tag(4)
        }
        .onChange(of: selectedTab) { _ in
            Haptic.tap() // 💥 vibra cada vez que cambias de pestaña
        }
    }
}
