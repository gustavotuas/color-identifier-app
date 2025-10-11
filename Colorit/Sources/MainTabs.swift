import SwiftUI

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
                        // Solo cambiamos el flag global
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

// MARK: - Perfil
struct ProfileScreen: View {
    var body: some View {
        Form {
            Section("Legal") {
                Link("Terms", destination: URL(string: "https://example.com/terms")!)
                Link("Privacy", destination: URL(string: "https://example.com/privacy")!)
            }
            Section("Support") {
                Link("Contact", destination: URL(string: "mailto:support@example.com")!)
            }
        }
        .navigationTitle(NSLocalizedString("profile", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pestañas principales
struct MainTabs: View {
    var body: some View {
        TabView {

            NavigationStack { BrowseScreen() }
                .tabItem {
                    Label(NSLocalizedString("search", comment: ""), systemImage: "magnifyingglass")
                }

            NavigationStack { FavoritesScreen() }
                .tabItem {
                    Label(NSLocalizedString("favorites", comment: ""), systemImage: "heart")
                }

            NavigationStack { CameraScreen() }
                .tabItem {
                    Label(NSLocalizedString("camera", comment: ""), systemImage: "camera")
                }

            NavigationStack { PhotosScreen() }
                .tabItem {
                    Label(NSLocalizedString("photo", comment: ""), systemImage: "photo")
                }

            NavigationStack { ProfileScreen() }
                .tabItem {
                    Label(NSLocalizedString("profile", comment: ""), systemImage: "person.crop.circle")
                }
        }
    }
}
