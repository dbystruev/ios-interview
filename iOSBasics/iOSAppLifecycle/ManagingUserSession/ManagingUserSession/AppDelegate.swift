//
//  AppDelegate.swift
//  ManagingUserSession
//
//  Created by Denis Bystruev on 10/13/26.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    let sessionManager = SessionManager.shared
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        log(application, launchOptions as Any)
        sessionManager.initialize()
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        log(application)
        // Save last active timestamp
        sessionManager.saveLastActiveTime()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        log(application)
        // Check if session expired
        if sessionManager.isSessionExpired() {
            sessionManager.logout()
            showLoginScreen()
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        log(application)
        sessionManager.cleanup()
    }
    
    private func showLoginScreen() {
        log("Navigate to login")
    }
}
