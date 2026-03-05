import SwiftUI
import StoreKit
import Combine

// Comment IAP 03-04-2026
@MainActor
final class TrialManager: ObservableObject {
    static let shared = TrialManager()

    private enum Keys {
        static let freePlaysRemaining = "freePlaysRemaining"
        static let hasUnlockedFullGame = "hasUnlockedFullGame"
    }

    private static let unlockProductID = "unlock_full_game"

    // Users who owned the old paid app before this date are auto-unlocked.
    // Adjust if your paid->free migration date changes.
    private static let paidToFreeMigrationDate: Date = {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: "2026-03-04T00:00:00Z") ?? .distantPast
    }()

    #if DEBUG
    private static let defaultFreePlays = 3
    #else
    private static let defaultFreePlays = 15
    #endif

    @Published private(set) var freePlaysRemaining: Int
    @Published private(set) var hasUnlockedFullGame: Bool
    @Published private(set) var unlockProduct: Product?
    @Published private(set) var isLoadingStoreData = false
    @Published var lastStoreError: String?

    private let userDefaults: UserDefaults

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let persistedPlays = userDefaults.object(forKey: Keys.freePlaysRemaining) as? Int {
            self.freePlaysRemaining = max(0, persistedPlays)
        } else {
            self.freePlaysRemaining = Self.defaultFreePlays
        }

        self.hasUnlockedFullGame = userDefaults.bool(forKey: Keys.hasUnlockedFullGame)
    }

    // MARK: - Trial logic

    func canStartGame() -> Bool {
        hasUnlockedFullGame || freePlaysRemaining > 0
    }

    func registerGamePlay() {
        guard !hasUnlockedFullGame else { return }
        guard freePlaysRemaining > 0 else { return }
        freePlaysRemaining -= 1
        persist()
    }

    func isTrialExpired() -> Bool {
        !hasUnlockedFullGame && freePlaysRemaining <= 0
    }

    func shouldShowFivePlaysWarning() -> Bool {
        !hasUnlockedFullGame && freePlaysRemaining == 5
    }

    // MARK: - Store setup

    func refreshStoreState() async {
        isLoadingStoreData = true
        lastStoreError = nil
        defer { isLoadingStoreData = false }

        await loadProduct()
        await refreshEntitlements()
    }

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.unlockProductID])
            unlockProduct = products.first
        } catch {
            lastStoreError = "Kunne ikke hente købsmuligheder lige nu."
        }
    }

    // MARK: - Purchase flow

    @discardableResult
    func purchaseFullGame() async -> Bool {
        do {
            if unlockProduct == nil {
                await loadProduct()
            }

            guard let product = unlockProduct else {
                lastStoreError = "Produktet kunne ikke findes."
                return false
            }

            let purchaseResult = try await product.purchase()
            switch purchaseResult {
            case .success(let verificationResult):
                let transaction = try verify(verificationResult)
                await transaction.finish()
                unlockPermanently()
                return true

            case .pending:
                lastStoreError = "Købet afventer godkendelse."
                return false

            case .userCancelled:
                return false

            @unknown default:
                lastStoreError = "Købet kunne ikke gennemføres."
                return false
            }
        } catch {
            lastStoreError = "Der opstod en fejl under køb."
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return hasUnlockedFullGame
        } catch {
            lastStoreError = "Kunne ikke genskabe køb lige nu."
            return false
        }
    }

    func refreshEntitlements() async {
        // Non-consumable entitlement from StoreKit
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.unlockProductID {
                unlockPermanently()
                return
            }
        }

        // Legacy paid app users
        if await hasLegacyPaidEntitlement() {
            unlockPermanently()
        }
    }

    private func hasLegacyPaidEntitlement() async -> Bool {
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let appTransaction) = result else { return false }
            return appTransaction.originalPurchaseDate < Self.paidToFreeMigrationDate
        } catch {
            return false
        }
    }

    private func unlockPermanently() {
        guard !hasUnlockedFullGame else { return }
        hasUnlockedFullGame = true
        persist()
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreVerificationError.failed
        }
    }

    private func persist() {
        userDefaults.set(freePlaysRemaining, forKey: Keys.freePlaysRemaining)
        userDefaults.set(hasUnlockedFullGame, forKey: Keys.hasUnlockedFullGame)
    }

    private enum StoreVerificationError: Error {
        case failed
    }

    // MARK: - Debug helpers

    #if DEBUG
    func resetTrial() {
        freePlaysRemaining = Self.defaultFreePlays
        hasUnlockedFullGame = false
        persist()
    }

    func simulatePurchase() {
        unlockPermanently()
    }

    func printCurrentTrialStatus() {
        print("[TrialManager] freePlaysRemaining=\(freePlaysRemaining), hasUnlockedFullGame=\(hasUnlockedFullGame), isTrialExpired=\(isTrialExpired())")
    }
    #endif
}
