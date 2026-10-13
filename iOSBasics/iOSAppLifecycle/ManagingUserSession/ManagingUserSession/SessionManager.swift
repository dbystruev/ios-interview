//
//  SessionManager.swift
//  ManagingUserSession
//
//  Created by Denis Bystruev on 10/13/26.
//
//  Derived from https://github.com/mukundjogi/ios-interview/blob/main/docs/ios-basics.md#practical-example-managing-user-session

import Foundation

class SessionManager {
    static let shared = SessionManager()
    private let sessionTimeout: TimeInterval = 15 * 60 // 15 minutes
    private let lastActiveKey = "lastActiveTime"
    
    func initialize() {
        log("Load saved session")
    }
    
    func saveLastActiveTime() {
        let date = Date()
        log(date)
        UserDefaults.standard.set(date, forKey: lastActiveKey)
    }
    
    func isSessionExpired() -> Bool {
        guard let lastActive = UserDefaults.standard.object(forKey: lastActiveKey) as? Date else {
            log(true)
            return true
        }
        let expired = sessionTimeout < Date().timeIntervalSince(lastActive)
        log(expired)
        return expired
    }
    
    func logout() {
        log()
        // Clear session data
        UserDefaults.standard.removeObject(forKey: lastActiveKey)
    }
    
    func cleanup() {
        log("Cleanup resources")
    }
}
