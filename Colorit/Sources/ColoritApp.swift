import SwiftUI

@main
struct ColoritApp: App {
    @StateObject var store = StoreVM()
    @StateObject var catalog = Catalog()
    @StateObject var favs = FavoritesStore()
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var catalogs = CatalogStore(preload: [.generic, .sherwinWilliams])

    var body: some Scene {
        WindowGroup {
            MainTabs()
                .environmentObject(store)
                .environmentObject(catalog)
                .environmentObject(favs)
                .environmentObject(catalogs)
                .task {
                    await store.load()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if !store.isPro {
                            store.showPaywall = true
                        }
                    }
                }

                .onChange(of: scenePhase) { phase in
                    if phase == .active && !store.isPro {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            store.showPaywall = true
                        }
                    }
                }
            
                .fullScreenCover(isPresented: $store.showPaywall) {
                    PaywallView()
                        .environmentObject(store)
                }
        }
    }
}
