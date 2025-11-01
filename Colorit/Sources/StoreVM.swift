//
//  StoreVM.swift
//  Colorit
//
//  Updated by Gustavo Tua on 11/10/25.
//

import SwiftUI
import StoreKit
import Combine

@MainActor
final class StoreVM: ObservableObject {
    // ✅ Persistente: se guarda entre sesiones
    @AppStorage("isPro") var isPro = false

    @Published var showPaywall = false
    @Published var products: [Product] = []
    @Published var selectedID: String? = nil
    @Published var isLaunchPromo = true
    @Published var isLoading = false

    // 🔑 IDs de tus productos reales
    let weekly = "com.colorit.app.weekly"
    let yearly = "com.colorit.app.yearly"

    init() {
        Task {
            await load()
            await refreshEntitlements()
        }
    }

    // MARK: - Cargar productos desde App Store
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: [weekly, yearly])
            if selectedID == nil {
                selectedID = yearly // 👈 Plan por defecto
            }
        } catch {
            print("❌ Store load error:", error)
        }
    }

    // MARK: - Verificar compras activas
    func refreshEntitlements() async {
        do {
            var hasActive = false
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    if [weekly, yearly].contains(transaction.productID),
                       transaction.revocationDate == nil {
                        hasActive = true
                    }
                }
            }
            isPro = hasActive
            print("🔁 Entitlements refreshed → isPro =", isPro)
        } catch {
            print("❌ Error checking entitlements:", error)
        }
    }

    // MARK: - Comprar producto seleccionado
    func buySelected() async {
        guard let id = selectedID,
              let product = products.first(where: { $0.id == id }) else { return }
        await buy(product)
    }

    @MainActor
    func buy(_ product: Product) async {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    // ✅ Compra verificada correctamente
                    isPro = true
                    showPaywall = false
                    await transaction.finish()
                    print("✅ Purchase successful:", product.id)
                }

            case .userCancelled:
                print("🟡 Purchase cancelled by user")
            default:
                print("⚠️ Purchase result:", result)
            }
        } catch {
            print("❌ Purchase failed:", error)
        }
    }

    // MARK: - Restaurar compras
    func restorePurchases() async {
        do {
            var restored = false
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   [weekly, yearly].contains(transaction.productID) {
                    isPro = true
                    restored = true
                    print("♻️ Restored:", transaction.productID)
                }
            }
            if !restored {
                print("ℹ️ No purchases to restore.")
            }
        } catch {
            print("❌ Restore failed:", error)
        }
    }

    // MARK: - Utilidades
    func hasTrial(_ p: Product) -> Bool {
        // Si quieres habilitar prueba gratis, ajusta aquí
        return p.id == yearly
    }

    func hasLaunchDiscount(_ p: Product) -> Bool {
        isLaunchPromo && (p.id == yearly)
    }

    func regularPriceText(_ p: Product) -> String {
        if p.id == yearly {
            return "Regular $119.99/year"
        }
        return ""
    }
}
