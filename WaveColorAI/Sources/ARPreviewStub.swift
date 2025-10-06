import SwiftUI
import ARKit

struct ARPreviewStub: View {
    @EnvironmentObject var store: StoreVM
    
    var body: some View {
        VStack(spacing: 12) {
            if !store.isPro {
                Text("Pro feature")
                    .font(.headline)
                Button("Unlock Pro") {
                    store.showPaywall = true
                }
            }
            
            Text("AR Preview")
                .font(.title2)
                .bold()
            
            if ARWorldTrackingConfiguration.isSupported {
                Text("ARKit placeholder ready. Replace with real AR view (SceneKit/RealityKit) to paint walls.")
            } else {
                Text("AR not supported on this device.")
            }
            
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 220)
        }
        .padding()
    }
}

