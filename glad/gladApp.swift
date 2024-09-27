//
//  gladApp.swift
//  glad
//
//  Created by bytedance on 9/28/24.
//

import SwiftUI
import os

@main
struct gladApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ExceptionHandler")
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        setupExceptionHandling()
        return true
    }
    
    private func setupExceptionHandling() {
        NSSetUncaughtExceptionHandler { exception in
            AppDelegate.handleException(exception)
        }
    }
    
    static func handleException(_ exception: NSException) {
        logger.fault("Uncaught exception: \(exception.name.rawValue), reason: \(exception.reason ?? "Unknown reason")")
    }
}
