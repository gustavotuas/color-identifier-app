import SwiftUI
import StoreKit

// MARK: - Helper para alertas
struct AlertMessage: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - PaywallView
struct PaywallView: View {
    @EnvironmentObject var store: StoreVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showClose = false
    @State private var canDismiss = false
    @State private var pulse = false
    @State private var restoreMessage: AlertMessage? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(.systemBackground), Color(.secondarySystemBackground)]
                    : [Color(red: 0.97, green: 0.98, blue: 1.0),
                       Color(red: 0.94, green: 0.95, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {

                        // HEADER
                        VStack(spacing: 8) {
                            HStack {
                                if showClose {
                                    Button {
                                        dismiss()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.leading, 8)
                                }
                                Spacer()
                            }

                            Text("Unlock Pro Features")
                                .font(.system(size: 28, weight: .bold))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                                .padding(.top, 4)
                        }
                        .padding(.top, 12)

                        // PLANS
                        VStack(spacing: 12) {
                            ForEach(store.products.sorted(by: { a, b in
                                if a.id == store.yearly { return true }
                                if b.id == store.yearly { return false }
                                return a.price < b.price
                            }), id: \.id) { p in
                                SelectablePlanCard(
                                    product: p,
                                    isSelected: store.selectedID == p.id,
                                    pulse: pulse && p.id == store.yearly
                                )
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        store.selectedID = p.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        // FEATURES
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Included in Pro")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.leading, 4)

                            FeatureRow(icon: "camera.viewfinder", title: "Live Color ID",
                                       subtitle: "Identify colors instantly through your camera in real-time.", color: .green)
                            FeatureRow(icon: "photo.on.rectangle.angled", title: "Photo Color Picker",
                                       subtitle: "Extract professional palettes from any photo with AI precision.", color: .orange)
                            FeatureRow(icon: "paintpalette.fill", title: "Professional Paint Catalogues",
                                       subtitle: "Explore curated palettes from multiple paint collections.", color: .pink)
                            FeatureRow(icon: "heart.text.square.fill", title: "Unlimited Collections & Palettes",
                                       subtitle: "Create and organise unlimited palettes for your work or inspiration.", color: .red)
                            FeatureRow(icon: "magnifyingglass", title: "Advanced Search",
                                       subtitle: "Find colors by HEX, RGB, or name instantly and intuitively.", color: .blue)
                            FeatureRow(icon: "circle.hexagongrid.fill", title: "Harmony & Similar Colors",
                                       subtitle: "Generate harmonic schemes and discover matching tones easily.", color: .indigo)
                            FeatureRow(icon: "square.grid.2x2", title: "Multiple Layout Views",
                                       subtitle: "Switch between grid and list layouts to explore palettes visually.", color: .purple)
                            FeatureRow(icon: "wand.and.stars", title: "Smart Filters & Sorting",
                                       subtitle: "Filter by hue, brightness, or harmony with precision.", color: .teal)
                            FeatureRow(icon: "photo.stack.fill", title: "Color Matches for Photo & Live ID",
                                       subtitle: "Compare and visualise matches between live and captured samples.", color: .cyan)
                            FeatureRow(icon: "lock.open.fill", title: "Unlimited Access",
                                       subtitle: "No restrictions — enjoy every tool, palette and feature forever.", color: .gray)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                    .padding(.bottom, 20)
                }

                // CTA + FOOTER
                VStack(spacing: 10) {
                    let selected = store.products.first(where: { $0.id == store.selectedID })
                    let buttonLabel = (selected?.id == store.weekly) ? "Continue" : "Try for Free"

                    AnimatedTryFreeButton(label: buttonLabel) {
                        Task { await store.buySelected() }
                    }

                    // RESTORE BUTTON WITH ALERT
                    Button {
                        Task {
                            await store.restorePurchases()
                            restoreMessage = AlertMessage(
                                text: store.isPro
                                    ? "Your purchases have been restored ✅"
                                    : "No previous purchases found."
                            )
                        }
                    } label: {
                        Text("Restore Purchases")
                            .font(.caption)
                            .underline()
                            .foregroundColor(.blue)
                    }
                    .alert(item: $restoreMessage) { message in
                        Alert(title: Text(message.text))
                    }

                    HStack {
                        Label("Cancel anytime", systemImage: "checkmark.circle")
                        Spacer()
                        Label("Family Sharing Enabled", systemImage: "person.3.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)

                    HStack(spacing: 18) {
                        Link("Terms of Use",
                             destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy Policy",
                             destination: URL(string: "https://www.coloritapp.com/privacy")!)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 25)
                .background(.ultraThinMaterial)
            }
        }
        .interactiveDismissDisabled(!canDismiss)
        .task {
            if store.products.isEmpty { await store.load() }
            if let yearly = store.products.first(where: { $0.id == store.yearly }) {
                store.selectedID = yearly.id
            }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeIn(duration: 0.3)) {
                    showClose = true
                    canDismiss = true
                }
            }
        }
    }
}

// MARK: - AnimatedTryFreeButton
struct AnimatedTryFreeButton: View {
    var label: String
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var animateGradient = false
    @State private var scaleUp = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                scaleUp.toggle()
            }
            action()
        }) {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color(hex: "#3C8CE7"), Color(hex: "#6F3CE7")]
                            : [Color(hex: "#6F3CE7"), Color(hex: "#FF61B6")],
                        startPoint: animateGradient ? .topLeading : .bottomTrailing,
                        endPoint: animateGradient ? .bottomTrailing : .topLeading
                    )
                )
                .cornerRadius(18)
                .foregroundColor(.white)
                .scaleEffect(scaleUp ? 1.04 : 1.0)
                .shadow(color: Color.purple.opacity(0.4), radius: 10, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) {
                        animateGradient.toggle()
                    }
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        scaleUp.toggle()
                    }
                }
        }
    }
}

// MARK: - SelectablePlanCard
struct SelectablePlanCard: View {
    @EnvironmentObject var store: StoreVM
    @Environment(\.colorScheme) private var scheme
    let product: Product
    let isSelected: Bool
    let pulse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle(for: product))
                        .font(.headline)
                        .foregroundColor(.primary)
                    if store.hasTrial(product) {
                        Text("Try for Free")
                            .font(.subheadline.bold())
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                if product.id == store.yearly {
                    Text("Best Value")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .scaleEffect(pulse ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "#6F3CE7"))
                        .scaleEffect(pulse ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                }
            }

            Text(product.displayPrice)
                .font(.title3.bold())
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            scheme == .dark ? Color(.secondarySystemBackground) : Color.white
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color(hex: "#6F3CE7") : Color.gray.opacity(0.25),
                        lineWidth: isSelected ? 3 : 1)
        )
        .cornerRadius(16)
        .shadow(
            color: scheme == .dark ? .white.opacity(0.04) : .black.opacity(0.08),
            radius: 4, x: 0, y: 1
        )
    }

    private func displayTitle(for product: Product) -> String {
        switch product.id {
        case store.yearly: return "1 Year"
        case store.weekly: return "1 Week"
        default: return product.displayName
        }
    }
}

// MARK: - FeatureRow
struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            scheme == .dark ? Color(.secondarySystemBackground) : Color.white
        )
        .cornerRadius(16)
        .shadow(
            color: scheme == .dark ? .white.opacity(0.03) : .black.opacity(0.08),
            radius: 4, x: 0, y: 2
        )
    }
}
