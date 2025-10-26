import SwiftUI
import UIKit

// MARK: - Helper para Haptic Feedback
final class Haptic {
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - Home Screen
struct HomeScreen: View {
    @EnvironmentObject var store: StoreVM

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Text("Colorit")
                    .font(.largeTitle)
                    .bold()

                GroupBox(NSLocalizedString("quick_actions", comment: "")) {
                    HStack {
                        NavigationLink(NSLocalizedString("open_camera", comment: "")) {
                            CameraScreen()
                        }
                        Spacer()
                    }
                }

                if !store.isPro {
                    Button(NSLocalizedString("unlock_pro", comment: "")) {
                        store.showPaywall = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationBarHidden(true)
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
                Label(NSLocalizedString("search", comment: ""), systemImage: "magnifyingglass")
            }
            .tag(0)

            // ❤️ Favorites
            NavigationStack {
                FavoritesScreen()
                    .environmentObject(favs)
                    .onAppear { favs.hasNewFavorites = false } // 👈 limpia el badge al entrar
            }
            .tabItem {
                Label(NSLocalizedString("Collections", comment: ""), systemImage: "rectangle.stack.fill")
            }
            .badge(favs.hasNewFavorites ? "●" : nil) // 👈 muestra el puntito de novedades
            .tag(1)

            // 📷 Camera
            NavigationStack {
                CameraScreen()
            }
            .tabItem {
                Label(NSLocalizedString("camera", comment: ""), systemImage: "camera")
            }
            .tag(2)

            // 🖼 Photos
            NavigationStack {
                PhotosScreen()
            }
            .tabItem {
                Label(NSLocalizedString("photo", comment: ""), systemImage: "photo")
            }
            .tag(3)

            // ⚙️ Settings
            NavigationStack {
                SettingScreen()
            }
            .tabItem {
                Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
            }
            .tag(4)
        }
        .onChange(of: selectedTab) { _ in
            Haptic.tap() // 💥 vibra cada vez que cambias de pestaña
        }
    }
}
