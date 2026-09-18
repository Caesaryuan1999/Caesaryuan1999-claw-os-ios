import UIKit

// Empty, separately bundled XCTest host. It never initializes the messaging App,
// credentials, Cache, Firebase, push, or a network service.
@main
final class VLCProbeHostAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        window.rootViewController = controller
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}
