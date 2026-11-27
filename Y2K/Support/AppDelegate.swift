//
//  AppDelegate.swift
//  y2k
//
//  Deliberately free of Firebase / StoreKit dependencies so the clone launches
//  on iOS 12 without Google's SDKs (Firebase 12.x requires iOS 15+).
//

import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // The original registers its custom fonts through Info.plist's UIAppFonts;
        // nothing else is required here.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

/// Hosts the gallery home screen.
final class RootViewController: UINavigationController {

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        viewControllers = [HomeViewController()]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        viewControllers = [HomeViewController()]
    }

    override var prefersStatusBarHidden: Bool { return false }
    override var preferredStatusBarStyle: UIStatusBarStyle { return .default }
}
