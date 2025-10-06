import SwiftUI
import StoreKit
import Combine

@MainActor
final class StoreVM: ObservableObject {
    @Published var isPro = false
    @Published var showPaywall = false
    @Published var products:[Product] = []
    @Published var selectedID: String? = nil
    @Published var isLaunchPromo = true

    let weekly = "com.wavecolorai.weekly"
    let monthly = "com.wavecolorai.monthly"
    let yearly = "com.wavecolorai.yearly"

    init() {
        Task { await load() }
    }

    func load() async {
        do {
            products = try await Product.products(for: [weekly, monthly, yearly])
            if selectedID == nil { selectedID = monthly }
            try await refresh()
        } catch { print("Store load:", error) }
    }

    func refresh() async throws {
        for await res in Transaction.currentEntitlements {
            if case .verified(let t) = res, [weekly, monthly, yearly].contains(t.productID) {
                isPro = true
            }
        }
    }

    func buySelected() async {
        guard let id = selectedID, let p = products.first(where: { $0.id == id }) else { return }
        await buy(p)
    }

    func buy(_ p: Product) async {
        do {
            let r = try await p.purchase()
            switch r {
            case .success(let ver):
                if case .verified(let t) = ver {
                    isPro = true
                    await t.finish()
                }
            default: break
            }
        } catch { print("Purchase:", error) }
    }

    func hasTrial(_ p: Product) -> Bool { p.id == monthly || p.id == yearly }
    func hasLaunchDiscount(_ p: Product) -> Bool { isLaunchPromo && (p.id == monthly || p.id == yearly) }
    func regularPriceText(_ p: Product) -> String {
        if p.id == monthly { return NSLocalizedString("regular_price_monthly", comment: "") }
        if p.id == yearly { return NSLocalizedString("regular_price_yearly", comment: "") }
        return ""
    }
}

struct PaywallView: View {
    @EnvironmentObject var store: StoreVM

    var body: some View {
        NavigationStack {
            VStack(spacing:16){
                Text(NSLocalizedString("unlock_title", comment: ""))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(NSLocalizedString("unlock_subtitle", comment: ""))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing:12) {
                    ForEach(store.products.sorted(by: { $0.price < $1.price }), id: \.id) { p in
                        PlanCard(product: p)
                            .onTapGesture { store.selectedID = p.id }
                    }
                }.padding(.horizontal)

                if let sel = store.products.first(where: { $0.id == store.selectedID }) {
                    if store.hasTrial(sel) {
                        Text(NSLocalizedString("trial_badge", comment: ""))
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    if store.hasLaunchDiscount(sel) {
                        Text(NSLocalizedString("discount_badge_today", comment: ""))
                            .font(.subheadline).foregroundColor(.pink)
                    }
                }

                Button(action: {
                    Task { await store.buySelected() }
                }) {
                    Text(NSLocalizedString("cta_start_trial_save", comment: ""))
                        .bold()
                        .frame(maxWidth:.infinity)
                        .padding()
                        .background(LinearGradient(colors:[.purple,.pink], startPoint:.leading, endPoint:.trailing))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)

                Text(NSLocalizedString("footer_note", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Pro")
            .task { await store.load() }
        }
    }
}

struct PlanCard: View {
    @EnvironmentObject var store: StoreVM
    let product: Product

    var title: String {
        switch product.id {
        case store.weekly: return NSLocalizedString("plan_weekly", comment: "")
        case store.monthly: return NSLocalizedString("plan_monthly", comment: "")
        case store.yearly: return NSLocalizedString("plan_yearly", comment: "")
        default: return product.displayName
        }
    }

    var body: some View {
        VStack(alignment:.leading, spacing:6){
            HStack {
                Text(title).font(.headline)
                Spacer()
                if store.selectedID == product.id {
                    Text(NSLocalizedString("selected", comment: ""))
                        .font(.caption).padding(6)
                        .background(Color.blue.opacity(0.15)).foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }
            Text(product.displayPrice).font(.title3).bold()

            if store.hasTrial(product) {
                Text(NSLocalizedString("trial_badge", comment: ""))
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            if store.hasLaunchDiscount(product) {
                Text(store.regularPriceText(product))
                    .font(.caption2)
                    .strikethrough()
                    .foregroundColor(.secondary)
                Text(NSLocalizedString("discount_badge_limited", comment: ""))
                    .font(.caption).foregroundColor(.pink)
            }
            if product.id == store.yearly {
                Text(NSLocalizedString("best_value", comment: ""))
                    .font(.caption).padding(6)
                    .background(Color.green.opacity(0.15)).foregroundColor(.green)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .frame(maxWidth:.infinity)
        .background(RoundedRectangle(cornerRadius:16).stroke(Color.blue, lineWidth: store.selectedID == product.id ? 3 : 1))
    }
}
