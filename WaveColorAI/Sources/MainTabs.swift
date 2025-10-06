import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject var store: StoreVM

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Título principal
                Text("WaveColorAI")
                    .font(.largeTitle)
                    .bold()
                
                // Acciones rápidas
                GroupBox(NSLocalizedString("quick_actions", comment: "")) {
                    HStack {
                        NavigationLink(NSLocalizedString("open_camera", comment: "")) {
                            CameraScreen()
                        }
                        Spacer()
                    }
                }
                
                // Botón de desbloqueo Pro
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
        .sheet(isPresented: $store.showPaywall) {
            PaywallView().environmentObject(store)
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
            NavigationStack { HomeScreen() }
                .tabItem {
                    Label(NSLocalizedString("home", comment: ""), systemImage: "house")
                }

            NavigationStack { CameraScreen() }
                .tabItem {
                    Label(NSLocalizedString("camera", comment: ""), systemImage: "camera")
                }

            NavigationStack { BrowseScreen() }
                .tabItem {
                    Label(NSLocalizedString("browse", comment: ""), systemImage: "rectangle.grid.2x2")
                }

            NavigationStack { FavoritesScreen() }
                .tabItem {
                    Label(NSLocalizedString("favorites", comment: ""), systemImage: "heart")
                }

            NavigationStack { ProfileScreen() }
                .tabItem {
                    Label(NSLocalizedString("profile", comment: ""), systemImage: "person.crop.circle")
                }
        }
    }
}
