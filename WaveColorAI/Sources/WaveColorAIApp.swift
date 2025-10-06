import SwiftUI

@main
struct WaveColorAIApp: App {
    @StateObject var store = StoreVM()
    @StateObject var catalog = Catalog()
    @StateObject var favs = FavoritesStore()
    @AppStorage("hasShownPaywall") var hasShownPaywall = false
    var body: some Scene {
        WindowGroup {
            MainTabs()
                .environmentObject(store)
                .environmentObject(catalog)
                .environmentObject(favs)
                .onAppear {
                    if !hasShownPaywall {
                        store.showPaywall = true
                        hasShownPaywall = true
                    }
                }
        }
    }
}
