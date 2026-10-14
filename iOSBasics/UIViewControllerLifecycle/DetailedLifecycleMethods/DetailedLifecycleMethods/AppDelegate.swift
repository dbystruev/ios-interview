//
//  AppDelegate.swift
//  DetailedLifecycleMethods
//
//  Created by Denis Bystruev on 10/14/26.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ExampleViewController()
        window.makeKeyAndVisible()
        self.window = window
        
        return true
    }
    
}
