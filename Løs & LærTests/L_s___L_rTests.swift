import XCTest
import StoreKitTest
@testable import Løs___Lær

@MainActor
final class LøsOgLærIAPTests: XCTestCase {
    private var session: SKTestSession!

    private let storeKitConfigPath = "/Users/thomaspedersen/Desktop/Xcode/Løs & Lær/Løs & Lær/StoreKitTest.storekit"
    private let freePlaysKey = "freePlaysRemaining"
    private let unlockKey = "hasUnlockedFullGame"

    private var trialManager: TrialManager { TrialManager.shared }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        session = try SKTestSession(contentsOf: URL(fileURLWithPath: storeKitConfigPath))
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.locale = Locale(identifier: "da_DK")
        session.storefront = "DNK"

        UserDefaults.standard.removeObject(forKey: freePlaysKey)
        UserDefaults.standard.removeObject(forKey: unlockKey)
        trialManager.resetTrial()
    }

    override func tearDownWithError() throws {
        session?.clearTransactions()
        UserDefaults.standard.removeObject(forKey: freePlaysKey)
        UserDefaults.standard.removeObject(forKey: unlockKey)
        session = nil
        try super.tearDownWithError()
    }

    func testPhase3_EndToEndPurchaseAndRestore() async throws {
        // 1) User launches app -> store state loads.
        await trialManager.refreshStoreState()
        XCTAssertNotNil(trialManager.unlockProduct, "StoreKit product unlock_full_game was not loaded.")
        XCTAssertFalse(trialManager.hasUnlockedFullGame)

        // 2) User reaches unlock screen by consuming free plays.
        while trialManager.canStartGame() {
            trialManager.registerGamePlay()
        }
        XCTAssertTrue(trialManager.isTrialExpired(), "Trial should be expired before purchase.")

        // 3) User purchases unlock_full_game via local StoreKit test session.
        // This is the non-interactive equivalent of tapping "Lås op" in UI.
        try session.buyProduct(productIdentifier: "unlock_full_game")

        // 4) Game unlocks immediately after entitlement refresh.
        await trialManager.refreshEntitlements()
        XCTAssertTrue(trialManager.hasUnlockedFullGame, "Unlock state was not set immediately after purchase.")
        XCTAssertTrue(trialManager.canStartGame(), "Unlocked user should always be able to start games.")

        // 5-6) App restart equivalent -> persisted unlock flag must be true.
        XCTAssertTrue(UserDefaults.standard.bool(forKey: unlockKey), "Unlock flag was not persisted in UserDefaults.")

        // 7) Restore purchase equivalent -> should re-unlock from entitlement history.
        trialManager.resetTrial()
        XCTAssertFalse(trialManager.hasUnlockedFullGame, "Reset trial should clear unlock before restore test.")

        await trialManager.refreshEntitlements()
        XCTAssertTrue(trialManager.hasUnlockedFullGame, "Restore did not re-unlock the full game.")
    }
}
