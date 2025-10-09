import SwiftUI

@main
struct WaveColorAIApp: App {
    @StateObject var store = StoreVM()
    @StateObject var catalog = Catalog()
    @StateObject var favs = FavoritesStore()

    @State private var showPaywall = false

    var body: some Scene {
        WindowGroup {
            MainTabs()
                .environmentObject(store)
                .environmentObject(catalog)
                .environmentObject(favs)
                .onAppear {
                    triggerPaywall()
                }
                .task {
                    await store.load()
                    triggerPaywall()
                }
                .fullScreenCover(isPresented: $showPaywall) {
                    PaywallView()
                        .environmentObject(store)
                }
        }
    }

    private func triggerPaywall() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !store.isPro {
                showPaywall = true
            } else {
                showPaywall = false
            }
        }
    }
}
