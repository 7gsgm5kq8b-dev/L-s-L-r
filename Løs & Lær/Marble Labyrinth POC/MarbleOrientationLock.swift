import ObjectiveC.runtime
import SwiftUI
import UIKit

final class MarbleOrientationAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MarbleOrientationLock.currentMask
    }
}

enum MarbleOrientationLock {
    static var currentMask: UIInterfaceOrientationMask = .all
    static let gameplayOrientation: UIInterfaceOrientation = .landscapeRight

    fileprivate static var isGameplayLocked = false

    private static var didInstallRotationHooks = false
    private static var swizzledSelectors: Set<String> = []

    static func lockGameplayOrientation() {
        installRotationHooksIfNeeded()
        isGameplayLocked = true
        currentMask = .landscapeRight
        enforceLockedOrientation()
    }

    static func unlockAppOrientation() {
        isGameplayLocked = false
        currentMask = .all
        requestRotation(mask: .all, preferredOrientation: nil)
    }

    private static func enforceLockedOrientation() {
        requestRotation(mask: .landscapeRight, preferredOrientation: gameplayOrientation)
    }

    private static func requestRotation(mask: UIInterfaceOrientationMask, preferredOrientation: UIInterfaceOrientation?) {
        guard let windowScene = activeWindowScene() else {
            return
        }

        if let preferredOrientation {
            UIDevice.current.setValue(preferredOrientation.rawValue, forKey: "orientation")
        }

        refreshOrientationControllers(in: windowScene)

        if #available(iOS 16.0, *) {
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            windowScene.requestGeometryUpdate(preferences) { _ in }
        }

        refreshOrientationControllers(in: windowScene)
        UIViewController.attemptRotationToDeviceOrientation()
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

    private static func refreshOrientationControllers(in windowScene: UIWindowScene) {
        for window in windowScene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            window.rootViewController?.navigationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            window.rootViewController?.children.forEach { $0.setNeedsUpdateOfSupportedInterfaceOrientations() }
        }
    }

    private static func installRotationHooksIfNeeded() {
        guard !didInstallRotationHooks else { return }
        didInstallRotationHooks = true

        swizzle(
            on: UIViewController.self,
            original: #selector(getter: UIViewController.shouldAutorotate),
            replacement: #selector(UIViewController.marble_shouldAutorotate)
        )

        swizzle(
            on: UIViewController.self,
            original: #selector(getter: UIViewController.supportedInterfaceOrientations),
            replacement: #selector(UIViewController.marble_supportedInterfaceOrientations)
        )

        swizzle(
            on: UIViewController.self,
            original: #selector(getter: UIViewController.preferredInterfaceOrientationForPresentation),
            replacement: #selector(UIViewController.marble_preferredInterfaceOrientationForPresentation)
        )

        swizzle(
            on: UINavigationController.self,
            original: #selector(getter: UIViewController.shouldAutorotate),
            replacement: #selector(UINavigationController.marble_shouldAutorotate)
        )

        swizzle(
            on: UINavigationController.self,
            original: #selector(getter: UIViewController.supportedInterfaceOrientations),
            replacement: #selector(UINavigationController.marble_supportedInterfaceOrientations)
        )

        swizzle(
            on: UINavigationController.self,
            original: #selector(getter: UIViewController.preferredInterfaceOrientationForPresentation),
            replacement: #selector(UINavigationController.marble_preferredInterfaceOrientationForPresentation)
        )
    }

    private static func swizzle(on type: AnyClass, original: Selector, replacement: Selector) {
        let key = "\(NSStringFromClass(type))|\(NSStringFromSelector(original))"
        guard !swizzledSelectors.contains(key) else { return }

        guard
            let originalMethod = class_getInstanceMethod(type, original),
            let replacementMethod = class_getInstanceMethod(UIViewController.self, replacement)
        else { return }

        let added = class_addMethod(
            type,
            original,
            method_getImplementation(replacementMethod),
            method_getTypeEncoding(replacementMethod)
        )

        if added {
            class_replaceMethod(
                type,
                replacement,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }

        swizzledSelectors.insert(key)
    }
}

private extension UIViewController {
    @objc func marble_shouldAutorotate() -> Bool {
        if MarbleOrientationLock.isGameplayLocked {
            return false
        }

        return marble_shouldAutorotate()
    }

    @objc func marble_supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        if MarbleOrientationLock.isGameplayLocked {
            return MarbleOrientationLock.currentMask
        }

        return marble_supportedInterfaceOrientations()
    }

    @objc func marble_preferredInterfaceOrientationForPresentation() -> UIInterfaceOrientation {
        if MarbleOrientationLock.isGameplayLocked {
            return MarbleOrientationLock.gameplayOrientation
        }

        return marble_preferredInterfaceOrientationForPresentation()
    }
}
