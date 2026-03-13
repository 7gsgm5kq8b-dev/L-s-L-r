//___FILEHEADER___

import SwiftUI
import UIKit

@main
struct PlayAndLearn: App {
    @UIApplicationDelegateAdaptor(MarbleOrientationAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
