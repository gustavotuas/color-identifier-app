import SwiftUI
import StoreKit

// MARK: - PaywallView
struct PaywallView: View {
    @EnvironmentObject var store: StoreVM
    @Environment(\.dismiss) private var dismiss
    @State private var showClose = false
    @State private var canDismiss = false
    @State private var currentReview = 0

    // ✅ Reviews embebidas en memoria
    private let reviews: [(stars: String, text: String)] = [
        ("⭐️⭐️⭐️⭐️⭐️", "The upgrade was worth it just for the paint colours."),
        ("⭐️⭐️⭐️⭐️⭐️", "This app completely changed how I work with palettes."),
        ("⭐️⭐️⭐️⭐️⭐️", "Simple, smart and beautiful. Highly recommend it!"),
        ("⭐️⭐️⭐️⭐️⭐️", "Love how accurate the color matching is. Worth every penny!")
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.95, green: 0.96, blue: 1.0),
                Color(red: 0.93, green: 0.94, blue: 1.0)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // SCROLLABLE CONTENT
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {

                        // HEADER
                        VStack(spacing: 6) {
                            HStack {
                                if showClose {
                                    Button {
                                        dismiss()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.gray.opacity(0.6))
                                    }
                                    .padding(.leading, 8)
                                }
                                Spacer()
                            }

                            Text("Unlock Pro Features")
                                .font(.system(size: 26, weight: .bold))
                                .multilineTextAlignment(.center)
                                .padding(.top, showClose ? -6 : 0)
                        }
                        .padding(.top, topSafeAreaInset() + 6)

                        // REVIEWS SECTION
                        TabView(selection: $currentReview) {
                            ForEach(0..<reviews.count, id: \.self) { i in
                                VStack(spacing: 6) {
                                    Text(reviews[i].stars)
                                        .font(.title3)
                                    Text(reviews[i].text)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                                .frame(width: UIScreen.main.bounds.width - 80, height: 80)
                                .background(Color.white)
                                .cornerRadius(14)
                                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                        .frame(height: 120)

                        // SELECTABLE PLANS
                        VStack(spacing: 12) {
                            ForEach(store.products.sorted(by: { a, b in
                                if a.id == store.yearly { return true } // Yearly primero
                                if b.id == store.yearly { return false }
                                return a.price < b.price
                            }), id: \.id) { product in
                                SelectablePlanCard(product: product, isSelected: store.selectedID == product.id)
                                    .onTapGesture {
                                        withAnimation(.spring()) {
                                            store.selectedID = product.id
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)

                        // FEATURES
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Only in Pro:")
                                .font(.headline)
                            FeatureRow(icon: "camera.viewfinder",
                                       title: "Live Colour ID",
                                       subtitle: "Identify colours and matching paint colors in real-time using your camera.",
                                       color: .green)
                            FeatureRow(icon: "paintpalette.fill",
                                       title: "Paint Colours",
                                       subtitle: "Browse and search professional paint colours from major manufacturers.",
                                       color: .orange)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 120)
                    }
                    .padding(.bottom, 30)
                }

                // FIXED CTA BUTTON
                VStack(spacing: 8) {
                    Button {
                        Task { await store.buySelected() }
                    } label: {
                        let selected = selectedProduct()
                        Text(selectedButtonLabel(for: selected))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(colors: [.orange, .yellow],
                                               startPoint: .leading,
                                               endPoint: .trailing)
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
                    }

                    HStack {
                        Label("Cancel anytime", systemImage: "checkmark.circle")
                        Spacer()
                        Label("Family Sharing Enabled", systemImage: "person.3.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                .background(.ultraThinMaterial)
            }
        }
        .interactiveDismissDisabled(!canDismiss)
        .task {
            await store.load()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeIn(duration: 0.3)) {
                    showClose = true
                    canDismiss = true
                }
            }
        }
    }

    // MARK: - Helpers
    private func selectedProduct() -> Product? {
        store.products.first(where: { $0.id == store.selectedID })
    }

    private func selectedButtonLabel(for product: Product?) -> String {
        guard let p = product else { return "Subscribe" }
        if store.hasTrial(p) {
            return "Start 3-day Free Trial, then \(p.displayPrice)"
        } else {
            return "Subscribe for \(p.displayPrice)"
        }
    }

    private func topSafeAreaInset() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.top }
            .first ?? 44
    }
}

// MARK: - SelectablePlanCard
struct SelectablePlanCard: View {
    @EnvironmentObject var store: StoreVM
    let product: Product
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayTitle(for: product))
                    .font(.headline)
                Spacer()
                if product.id == store.yearly {
                    Text("Best Value")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }

            if store.hasTrial(product) {
                Text("3-day free trial")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }

            Text(product.displayPrice)
                .font(.title3.bold())

            if store.hasLaunchDiscount(product) {
                Text(store.regularPriceText(product))
                    .font(.caption)
                    .strikethrough()
                    .foregroundColor(.gray)
                Text("81% off today")
                    .font(.caption)
                    .foregroundColor(.pink)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2),
                        lineWidth: isSelected ? 3 : 1)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}
