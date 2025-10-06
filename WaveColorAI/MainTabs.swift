
import SwiftUI

struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { CameraScreen() }
                .tabItem { Label(NSLocalizedString("scan_tab", comment:""), systemImage:"camera") }
            NavigationStack { PhotosScreen() }
                .tabItem { Label(NSLocalizedString("photos_tab", comment:""), systemImage:"photo") }
            NavigationStack { DiscoverScreen() }
                .tabItem { Label(NSLocalizedString("discover_tab", comment:""), systemImage:"sparkles") }
        }
    }
}
