import SwiftUI

@main
struct WaveColorAIApp: App {
    @StateObject var store = StoreVM()
    @StateObject var catalog = Catalog()
    @StateObject var favs = FavoritesStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabs()
                .environmentObject(store)
                .environmentObject(catalog)
                .environmentObject(favs)
                .task {
                    await store.load()
                    // Primer arranque: muestra paywall si no es PRO
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if !store.isPro {
                            store.showPaywall = true
                        }
                    }
                }
                // Cada vez que vuelve a estar activa la app (foreground)
                .onChange(of: scenePhase) { phase in
                    if phase == .active && !store.isPro {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            // Un único lugar controla la presentación
                            store.showPaywall = true
                        }
                    }
                }
                // ÚNICO presentador del Paywall en toda la app
                .fullScreenCover(isPresented: $store.showPaywall) {
                    PaywallView().environmentObject(store)
                }
        }
    }
}
