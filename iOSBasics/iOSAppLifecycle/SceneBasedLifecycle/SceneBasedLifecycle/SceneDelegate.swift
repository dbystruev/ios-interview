//
//  SceneDelegate.swift
//  SceneBasedLifecycle
//
//  Created by Denis Bystruev on 10/12/26.
//
//  Derived from https://github.com/mukundjogi/ios-interview/blob/main/docs/ios-basics.md#scene-based-lifecycle-ios-13

import UIKit

@main
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // Scene is connecting
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        log(scene, session, connectionOptions)
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(
            rootViewController: HomeViewController()
        )
        window.makeKeyAndVisible()
        self.window = window
    }

    // Scene became active
    func sceneDidBecomeActive(_ scene: UIScene) {
        log(scene)
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    // Scene will resign active
    func sceneWillResignActive(_ scene: UIScene) {
        log(scene)
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    // Scene entered foreground
    func sceneWillEnterForeground(_ scene: UIScene) {
        log(scene)
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    // Scene entered background
    func sceneDidEnterBackground(_ scene: UIScene) {
        log(scene)
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
    
    // Scene disconnected
    func sceneDidDisconnect(_ scene: UIScene) {
        log(scene)
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

}

// Provides main() function
extension SceneDelegate: UIApplicationDelegate {}
