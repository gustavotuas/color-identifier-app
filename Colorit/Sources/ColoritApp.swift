//
//  ColoritApp.swift
//  Colorit
//
//  Updated by ChatGPT on 11/10/25.
//

import SwiftUI

@main
struct ColoritApp: App {
    @StateObject var store = StoreVM()
    @StateObject var catalog = Catalog()
    @StateObject var favs = FavoritesStore()
    @StateObject private var theme = ThemeManager()
    @StateObject private var languageManager = LanguageManager()
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var catalogs = CatalogStore(preload: [.generic, .sherwinWilliams, .behr, .benjamin])

    var body: some Scene {
        WindowGroup {
            MainTabs()
                .environmentObject(store)
                .environmentObject(catalog)
                .environmentObject(favs)
                .environmentObject(catalogs)
                .environmentObject(theme)
                .environmentObject(languageManager)
                .id(languageManager.selectedLanguageCode)
                .preferredColorScheme(theme.selectedTheme.colorScheme)

                // ✅ Ya no necesitas llamar a store.load(), se hace en el init
                .task {
                    // Pequeña espera para refrescar la UI si el usuario no es Pro
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if !store.isPro {
                            store.showPaywall = true
                        }
                    }
                }

                // ✅ Al volver a la app, revalidar estado Pro (por si restauró compras o cambió dispositivo)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task {
                            await store.refreshEntitlements()
                        }

                        if !store.isPro {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                store.showPaywall = true
                            }
                        }
                    }
                }

                // ✅ Paywall full screen
                .fullScreenCover(isPresented: $store.showPaywall) {
                    PaywallView()
                        .environmentObject(store)
                }
        }
    }
}
