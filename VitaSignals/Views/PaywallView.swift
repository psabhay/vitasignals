import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var storeManager: StoreManager
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    trialExpiredBanner
                    planCards
                    legalSection
                }
                .padding()
            }
            .navigationTitle("VitaSignals")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Continue with VitaSignals")
                .font(.title2.bold())

            Text("Track your health, visualize trends, and generate reports for your doctor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    // MARK: - Trial Banner

    private var trialExpiredBanner: some View {
        let hasExpiredTrial = !storeManager.isTrialActive && storeManager.trialDaysRemaining == 0
            && UserDefaults.standard.object(forKey: "firstLaunchDate") != nil

        return HStack(spacing: 10) {
            Image(systemName: hasExpiredTrial ? "clock.badge.exclamationmark" : "gift")
                .foregroundStyle(hasExpiredTrial ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(hasExpiredTrial ? "Free trial ended" : "Start your free trial")
                    .font(.subheadline.bold())
                Text(hasExpiredTrial
                    ? "Your 30-day free trial has expired. Subscribe to keep using VitaSignals."
                    : "Subscribe now and enjoy 30 days free. Cancel anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((hasExpiredTrial ? Color.orange : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        VStack(spacing: 12) {
            if storeManager.isLoading {
                ProgressView("Loading plans...")
                    .padding(.vertical, 40)
            } else if storeManager.products.isEmpty {
                VStack(spacing: 8) {
                    Text("Unable to load subscription plans")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Please check your internet connection and try again.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await storeManager.loadProducts() }
                    }
                }
                .padding(.vertical, 20)
            } else {
                ForEach(storeManager.products, id: \.id) { product in
                    planCard(product)
                }

                purchaseButton

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Button {
                Task { await storeManager.restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 4)
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id
        let isYearly = product.id == StoreManager.yearlyID

        return Button {
            selectedProduct = product
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yearly" : "Monthly")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if isYearly {
                            Text("Save 42%")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.green, in: Capsule())
                        }
                    }
                    Text(product.displayPrice + (isYearly ? "/year" : "/month"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isYearly {
                        let monthly = product.price / 12
                        Text("~\(monthly.formatted(.currency(code: product.priceFormatStyle.currencyCode)))/month")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding()
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if selectedProduct == nil && isYearly {
                selectedProduct = product
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            isPurchasing = true
            errorMessage = nil
            Task {
                do {
                    let success = try await storeManager.purchase(product)
                    isPurchasing = false
                    if !success {
                        errorMessage = nil
                    }
                } catch {
                    isPurchasing = false
                    errorMessage = "Purchase failed. Please try again."
                }
            }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Subscribe")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                selectedProduct != nil ? Color.accentColor : Color.gray,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(.white)
        }
        .disabled(selectedProduct == nil || isPurchasing)
    }

    // MARK: - Legal

    private var legalSection: some View {
        VStack(spacing: 8) {
            Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. You can manage or cancel your subscription in your Apple ID settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                if let privacyURL = URL(string: "https://vitasignals.app/#privacy") {
                    Link("Privacy Policy", destination: privacyURL)
                        .font(.caption2)
                }
                if let termsURL = URL(string: "https://vitasignals.app/#terms-of-service") {
                    Link("Terms of Service", destination: termsURL)
                        .font(.caption2)
                }
            }
        }
        .padding(.top, 8)
    }
}
