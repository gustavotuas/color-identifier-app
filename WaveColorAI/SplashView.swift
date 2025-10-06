
import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0.0
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Image("AppIcon_Splash")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 220)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.9)) {
                        scale = 1.0
                        opacity = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeIn(duration: 0.2)) { opacity = 0.0 }
                        onFinish()
                    }
                }
        }
        .preferredColorScheme(.light)
    }
}
