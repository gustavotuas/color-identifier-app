//
//  StoreVM.swift
//  Colorit
//
//  Created by Gustavo  Tua on 9/10/25.
//

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

    @MainActor
    func buy(_ p: Product) async {
        do {
            let r = try await p.purchase()
            switch r {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    isPro = true
                    await transaction.finish()
                    // 🔥 Nueva línea: cierra el Paywall automáticamente
                    showPaywall = false
                }
            case .userCancelled:
                print("User cancelled purchase")
            default:
                break
            }
        } catch {
            print("Purchase failed:", error)
        }
    }


    func hasTrial(_ p: Product) -> Bool { p.id == monthly || p.id == yearly }
    func hasLaunchDiscount(_ p: Product) -> Bool { isLaunchPromo && (p.id == monthly || p.id == yearly) }
    func regularPriceText(_ p: Product) -> String {
        if p.id == monthly { return NSLocalizedString("regular_price_monthly", comment: "") }
        if p.id == yearly { return NSLocalizedString("regular_price_yearly", comment: "") }
        return ""
    }
}
