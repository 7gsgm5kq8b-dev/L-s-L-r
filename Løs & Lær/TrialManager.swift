import SwiftUI
import StoreKit
import Combine
import Security

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
    private let keychain: KeychainStore

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.keychain = KeychainStore(service: Bundle.main.bundleIdentifier ?? "o0Pedersen0o.L-s---L-r")

        let persistedPlays = keychain.int(forKey: Keys.freePlaysRemaining)
            ?? (userDefaults.object(forKey: Keys.freePlaysRemaining) as? Int)
        self.freePlaysRemaining = max(0, persistedPlays ?? Self.defaultFreePlays)

        let persistedUnlock = keychain.bool(forKey: Keys.hasUnlockedFullGame)
            ?? userDefaults.object(forKey: Keys.hasUnlockedFullGame) as? Bool
        self.hasUnlockedFullGame = persistedUnlock ?? false

        persist()
    }

    var configuredTrialPlayLimit: Int {
        Self.defaultFreePlays
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
        keychain.setInt(freePlaysRemaining, forKey: Keys.freePlaysRemaining)
        keychain.setBool(hasUnlockedFullGame, forKey: Keys.hasUnlockedFullGame)
    }

    private enum StoreVerificationError: Error {
        case failed
    }

    private struct KeychainStore {
        let service: String

        func int(forKey key: String) -> Int? {
            guard let value = string(forKey: key) else { return nil }
            return Int(value)
        }

        func bool(forKey key: String) -> Bool? {
            guard let value = string(forKey: key) else { return nil }
            return value == "1"
        }

        func setInt(_ value: Int, forKey key: String) {
            setString(String(value), forKey: key)
        }

        func setBool(_ value: Bool, forKey key: String) {
            setString(value ? "1" : "0", forKey: key)
        }

        private func string(forKey key: String) -> String? {
            var query = baseQuery(forKey: key)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else { return nil }
            return value
        }

        private func setString(_ value: String, forKey key: String) {
            let data = Data(value.utf8)
            let query = baseQuery(forKey: key)
            let attributes: [String: Any] = [kSecValueData as String: data]

            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecItemNotFound {
                var insertQuery = query
                insertQuery[kSecValueData as String] = data
                SecItemAdd(insertQuery as CFDictionary, nil)
            }
        }

        private func baseQuery(forKey key: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
        }
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
