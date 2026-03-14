import SwiftUI
import UIKit

final class MarbleOrientationAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MarbleOrientationLock.currentMask
    }
}

enum MarbleOrientationLock {
    static let appDefaultMask: UIInterfaceOrientationMask = orientationMaskFromInfoPlist() ?? .all
    static let gameplayMask: UIInterfaceOrientationMask = .landscapeRight
    static let gameplayOrientation: UIInterfaceOrientation = .landscapeRight

    static var currentMask: UIInterfaceOrientationMask = appDefaultMask

    static func lockGameplayOrientation(for controller: UIViewController) {
        currentMask = gameplayMask
        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        UIDevice.current.setValue(gameplayOrientation.rawValue, forKey: "orientation")
        requestGeometryUpdate(for: controller, mask: gameplayMask)
    }

    static func unlockAppOrientation(from controller: UIViewController?) {
        currentMask = appDefaultMask
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        requestGeometryUpdate(for: controller, mask: appDefaultMask)
    }

    private static func requestGeometryUpdate(for controller: UIViewController?, mask: UIInterfaceOrientationMask) {
        let scene = controller?.view.window?.windowScene ?? activeWindowScene()
        guard let scene else { return }

        if #available(iOS 16.0, *) {
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            scene.requestGeometryUpdate(preferences) { _ in }
        }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let activeKey = scenes.first(where: { $0.activationState == .foregroundActive && $0.windows.contains(where: { $0.isKeyWindow }) }) {
            return activeKey
        }

        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active
        }

        return scenes.first(where: { $0.activationState == .foregroundInactive })
    }

    private static func orientationMaskFromInfoPlist() -> UIInterfaceOrientationMask? {
        let info = Bundle.main.infoDictionary
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let key = isPad ? "UISupportedInterfaceOrientations~ipad" : "UISupportedInterfaceOrientations"
        let fallbackKey = "UISupportedInterfaceOrientations"
        let rawValues = (info?[key] as? [String]) ?? (info?[fallbackKey] as? [String])
        guard let rawValues, !rawValues.isEmpty else { return nil }

        var mask: UIInterfaceOrientationMask = []
        for rawValue in rawValues {
            switch rawValue {
            case "UIInterfaceOrientationPortrait":
                mask.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown":
                mask.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft":
                mask.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight":
                mask.insert(.landscapeRight)
            default:
                continue
            }
        }

        return mask.isEmpty ? nil : mask
    }
}

struct MarbleLabyrinthGameControllerContainer: UIViewControllerRepresentable {
    @EnvironmentObject var session: GameSessionManager

    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void

    func makeUIViewController(context: Context) -> MarbleLabyrinthGameEntryController {
        MarbleLabyrinthGameEntryController(
            session: session,
            difficulty: difficulty,
            startImmediately: startImmediately,
            onExit: onExit,
            onBackToHub: onBackToHub
        )
    }

    func updateUIViewController(_ uiViewController: MarbleLabyrinthGameEntryController, context: Context) {
        uiViewController.updateConfiguration(
            session: session,
            difficulty: difficulty,
            startImmediately: startImmediately,
            onExit: onExit,
            onBackToHub: onBackToHub
        )
    }
}

final class MarbleLabyrinthGameEntryController: UIViewController {
    private var session: GameSessionManager
    private var difficulty: Difficulty
    private var startImmediately: Bool
    private var onExit: () -> Void
    private var onBackToHub: () -> Void

    private weak var presentedGameController: MarbleLabyrinthGameHostingController?
    private var isPresentingGame = false
    private var didFinishSession = false

    init(
        session: GameSessionManager,
        difficulty: Difficulty,
        startImmediately: Bool,
        onExit: @escaping () -> Void,
        onBackToHub: @escaping () -> Void
    ) {
        self.session = session
        self.difficulty = difficulty
        self.startImmediately = startImmediately
        self.onExit = onExit
        self.onBackToHub = onBackToHub
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView(frame: .zero)
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentGameIfNeeded()
    }

    func updateConfiguration(
        session: GameSessionManager,
        difficulty: Difficulty,
        startImmediately: Bool,
        onExit: @escaping () -> Void,
        onBackToHub: @escaping () -> Void
    ) {
        self.session = session
        self.difficulty = difficulty
        self.startImmediately = startImmediately
        self.onExit = onExit
        self.onBackToHub = onBackToHub
        presentedGameController?.rootView = makeRootView()
    }

    private func presentGameIfNeeded() {
        guard presentedViewController == nil, !isPresentingGame, !didFinishSession else { return }
        isPresentingGame = true

        let controller = MarbleLabyrinthGameHostingController(rootView: makeRootView())
        controller.modalPresentationStyle = .fullScreen
        controller.isModalInPresentation = true
        presentedGameController = controller

        present(controller, animated: false) { [weak self] in
            self?.isPresentingGame = false
        }
    }

    private func makeRootView() -> AnyView {
        AnyView(
            MarbleLabyrinthPOCView(
                difficulty: difficulty,
                startImmediately: startImmediately,
                onExit: { [weak self] in
                    self?.finishSession(backToHub: false)
                },
                onBackToHub: { [weak self] in
                    self?.finishSession(backToHub: true)
                }
            )
            .environmentObject(session)
        )
    }

    private func finishSession(backToHub: Bool) {
        guard !didFinishSession else { return }
        didFinishSession = true

        let completion = backToHub ? onBackToHub : onExit

        if let gameController = presentedGameController, gameController.presentingViewController != nil {
            gameController.dismiss(animated: true) { [weak self] in
                self?.presentedGameController = nil
                completion()
            }
        } else {
            completion()
        }
    }
}

final class MarbleLabyrinthGameHostingController: UIHostingController<AnyView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        MarbleOrientationLock.gameplayMask
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        MarbleOrientationLock.gameplayOrientation
    }

    override var shouldAutorotate: Bool {
        false
    }

    @available(iOS 16.0, *)
    override var prefersInterfaceOrientationLocked: Bool {
        true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        MarbleOrientationLock.lockGameplayOrientation(for: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        MarbleOrientationLock.lockGameplayOrientation(for: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let leavingGame = isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true
        if leavingGame {
            MarbleOrientationLock.unlockAppOrientation(from: self)
        }
    }

    deinit {
        MarbleOrientationLock.unlockAppOrientation(from: nil)
    }
}
