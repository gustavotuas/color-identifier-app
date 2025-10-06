
import SwiftUI

@main
struct WaveColorAIApp: App {
    @State private var showSplash = true
    @StateObject private var store = StoreVM()

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashView { withAnimation { showSplash = false } }
                        .transition(.opacity)
                } else {
                    MainTabs().environmentObject(store)
                }
            }
        }
    }
}
