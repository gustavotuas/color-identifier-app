import SwiftUI

// MARK: - Toast View
struct ToastView: View {
    let message: String

    var body: some View {
        let bgColor: Color = {
            if message.contains("Added") { return Color.green.opacity(0.75) }
            if message.contains("Removed") { return Color.red.opacity(0.75) }
            if message.contains("Share") { return Color.blue.opacity(0.75) }
            return Color.gray.opacity(0.7)
        }()

        HStack(spacing: 10) {
            Image(systemName: iconForToast(message))
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline.bold())
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(bgColor, in: Capsule())
        .shadow(color: bgColor.opacity(0.4), radius: 6, y: 3)
        .padding(.bottom, 40)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale),
            removal: .opacity
        ))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: message)
    }

    private func iconForToast(_ message: String) -> String {
        switch message {
        case _ where message.contains("Copied"): return "doc.on.doc"
        case _ where message.contains("Added"): return "checkmark.circle.fill"
        case _ where message.contains("Removed"): return "trash.fill"
        case _ where message.contains("Share"): return "square.and.arrow.up"
        default: return "info.circle"
        }
    }
}

// MARK: - Toast Manager (modifier)
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let text = message {
                ToastView(message: text)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation { message = nil }
                        }
                    }
            }
        }
    }
}

// MARK: - Easy usage modifier
extension View {
    func toast(message: Binding<String?>) -> some View {
        self.modifier(ToastModifier(message: message))
    }
}
