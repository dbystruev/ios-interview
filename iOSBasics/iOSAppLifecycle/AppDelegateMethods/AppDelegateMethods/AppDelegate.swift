//
//  AppDelegate.swift
//  AppDelegateMethods
//
//  Created by Denis Bystruev on 10/11/26.
//
//  Derived from https://github.com/mukundjogi/ios-interview/blob/main/docs/ios-basics.md#app-delegate-methods

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?

    // 1. App is about to launch
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        log(application, launchOptions as Any)
        return true
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        log(application, launchOptions as Any)
        // Initialize app-wide resources
        setupAppearance()
        setupDatabase()
        return true
    }
    
    // 2. App will become active
    func applicationDidBecomeActive(_ application: UIApplication) {
        log(application)
        // Restart tasks, refresh UI
        startTimer()
        refreshData()
    }
    
    // 3. App will resign active (phone call, notification)
    func applicationWillResignActive(_ application: UIApplication) {
        log(application)
        // Pause ongoing tasks
        pauseTimer()
        saveState()
    }
    
    // 4. App entered background
    func applicationDidEnterBackground(_ application: UIApplication) {
        log(application)
        // Save data, release resources
        saveUserData()
        releaseResources()
        
        // Request additional background time if needed
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = application.beginBackgroundTask {
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        
        // Perform long-running task
        DispatchQueue.global().async {
            // Do work
            self.syncDataToServer()
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // 5. App will enter foreground
    func applicationWillEnterForeground(_ application: UIApplication) {
        log(application)
        // Undo background changes
        refreshUI()
    }
    
    // 6. App will terminate
    func applicationWillTerminate(_ application: UIApplication) {
        log(application)
        // Save final state
        saveAllData()
        cleanup()
    }

    // Supporting methods
    private func setupAppearance() {
        log()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
    
    private func setupDatabase() { log() }
    private func startTimer() { log() }
    private func refreshData() { log() }
    private func pauseTimer() { log() }
    private func saveState() { log() }
    private func saveUserData() { log() }
    private func releaseResources() { log() }
    private func syncDataToServer() { log() }
    private func refreshUI() { log() }
    private func saveAllData() { log() }
    private func cleanup() { log() }
}

