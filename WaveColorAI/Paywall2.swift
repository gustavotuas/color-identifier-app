
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var store: StoreVM
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(NSLocalizedString("paywall_title", comment: ""))
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)

                    if PaywallConfig.show50OffBadge {
                        Text(NSLocalizedString("launch_sale", comment: ""))
                            .font(.callout).foregroundStyle(.orange)
                    }

                    PlanRow(title: "1 Year", subtitle: "3-day free trial", price: PaywallConfig.yearlyPrice, badge: "Best Value") {
                        if let product = store.products.first(where: { $0.id.contains("yearly") }) {
                            Task { await store.purchase(product) }
                        }
                    }
                    PlanRow(title: "1 Month", subtitle: "3-day free trial", price: PaywallConfig.monthlyPrice, badge: nil) {
                        store.isPro = true; dismiss()
                    }
                    PlanRow(title: "1 Week", subtitle: nil, price: PaywallConfig.weeklyPrice, badge: nil) {
                        store.isPro = true; dismiss()
                    }

                    Text("Cancel anytime in the App Store.").font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .toolbar { ToolbarItem(placement:.topBarLeading) { Button("Close") { dismiss() } } }
        }
    }
}

private struct PlanRow: View {
    let title: String; let subtitle: String?; let price: String; let badge: String?
    let action: ()->Void
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment:.leading, spacing: 2) {
                    HStack {
                        Text(title).font(.headline)
                        if let b = badge {
                            Text(b).font(.caption2).padding(4).background(.blue.opacity(0.15)).clipShape(Capsule())
                        }
                    }
                    if let s = subtitle { Text(s).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(price).font(.headline)
                Image(systemName:"chevron.right").foregroundStyle(.secondary)
            }
            .padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}
