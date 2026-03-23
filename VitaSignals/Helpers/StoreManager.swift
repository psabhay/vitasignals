import Foundation
import StoreKit

@MainActor
final class StoreManager: ObservableObject {

    static let monthlyID = "com.weblerai.vitasignals.monthly"
    static let yearlyID = "com.weblerai.vitasignals.yearly"
    static let productIDs: Set<String> = [monthlyID, yearlyID]
    static let trialDurationDays = 30

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false

    private var transactionListener: Task<Void, Never>?

    // MARK: - Trial

    private static let firstLaunchKey = "firstLaunchDate"

    var firstLaunchDate: Date {
        if let stored = UserDefaults.standard.object(forKey: Self.firstLaunchKey) as? Date {
            return stored
        }
        let now = Date.now
        UserDefaults.standard.set(now, forKey: Self.firstLaunchKey)
        return now
    }

    var trialDaysRemaining: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: .now).day ?? 0
        return max(Self.trialDurationDays - elapsed, 0)
    }

    var isTrialActive: Bool {
        trialDaysRemaining > 0
    }

    // MARK: - Entitlement

    var isPremium: Bool {
        isTrialActive || !purchasedProductIDs.isEmpty
    }

    var currentPlan: String {
        if purchasedProductIDs.contains(Self.yearlyID) { return "Yearly" }
        if purchasedProductIDs.contains(Self.monthlyID) { return "Monthly" }
        if isTrialActive { return "Free Trial" }
        return "None"
    }

    // MARK: - Lifecycle

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            products = []
        }
        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await transaction.finish()
                    await self?.updatePurchasedProducts()
                }
            }
        }
    }

    // MARK: - Update Purchased Products

    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            }
        }
        purchasedProductIDs = purchased
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let value):
            return value
        }
    }

    enum StoreError: Error {
        case verificationFailed
    }
}
