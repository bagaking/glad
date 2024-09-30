//
//  gladApp.swift
//  glad
//
//  Created by bytedance on 9/28/24.
//

import SwiftUI
import os
import AVFoundation
import CloudKit

@main
struct gladApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "gladApp")
    
    init() {
        setupAudioSession()
        checkICloudStatus()
        setupCloudKitContainer()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio session setup successfully")
        } catch {
            print("Failed to set audio session category. Error: \(error)")
        }
    }
    
    private func checkICloudStatus() {
        CKContainer.default().accountStatus { (accountStatus, error) in
            if let error = error {
                logger.error("Error checking iCloud status: \(error.localizedDescription)")
                return
            }
            
            switch accountStatus {
            case .available:
                logger.info("iCloud is available")
            case .noAccount:
                logger.warning("No iCloud account")
            case .restricted:
                logger.warning("iCloud is restricted")
            case .couldNotDetermine:
                logger.error("Could not determine iCloud status")
            @unknown default:
                logger.error("Unknown iCloud account status")
            }
        }
    }
    
    private func setupCloudKitContainer() {
        let container = CKContainer.default()
        container.accountStatus { (accountStatus, error) in
            if let error = error {
                print("Error checking account status: \(error.localizedDescription)")
                return
            }
            
            switch accountStatus {
            case .available:
                print("iCloud is available")
                self.fetchUserRecord(container: container)
            case .noAccount:
                print("No iCloud account")
            case .restricted:
                print("iCloud is restricted")
            case .couldNotDetermine:
                print("Could not determine iCloud status")
            @unknown default:
                print("Unknown iCloud account status")
            }
        }
    }
    
    private func fetchUserRecord(container: CKContainer) {
        container.fetchUserRecordID { (recordID, error) in
            if let error = error {
                print("Error fetching user record: \(error.localizedDescription)")
                return
            }
            
            if let recordID = recordID {
                print("User record ID: \(recordID.recordName)")
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ExceptionHandler")
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        setupExceptionHandling()
        setupBackgroundModes(application)
        return true
    }
    
    private func setupExceptionHandling() {
        NSSetUncaughtExceptionHandler { exception in
            AppDelegate.handleException(exception)
        }
    }
    
    private func setupBackgroundModes(_ application: UIApplication) {
        application.beginReceivingRemoteControlEvents()
        
        // 启用后台音频播放
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            AppDelegate.logger.error("Failed to set audio session category. Error: \(error.localizedDescription)")
        }
    }
    
    static func handleException(_ exception: NSException) {
        logger.fault("Uncaught exception: \(exception.name.rawValue), reason: \(exception.reason ?? "Unknown reason")")
    }
}
