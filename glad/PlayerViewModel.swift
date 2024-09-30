import SwiftUI
import Photos
import os
import AVKit
import AVFoundation
import Combine

class PlayerViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var isPipActive = false
    var pipController: AVPictureInPictureController?
    @Published var playerLayer: AVPlayerLayer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PlayerViewModel")
    private var currentLoadingTask: Task<Void, Never>?
    @Published var pipError: String?
    @Published var preloadedAssets: [String: AVAsset] = [:]
    private let preloadQueue = DispatchQueue(label: "com.glad.preloadQueue", qos: .background)
    @Published var isPictureInPicturePossible = false
    @Published var isPictureInPictureActive = false
    private var pipPossibleObserver: NSKeyValueObservation?
    private var pipActiveObserver: NSKeyValueObservation?
    
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.defaultToSpeaker, .allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
            logger.info("Audio session setup successfully")
        } catch {
            logger.error("Failed to set audio session category. Error: \(error.localizedDescription)")
        }
    }
    
    func preloadAssets(_ assets: [PHAsset]) async {
        for asset in assets {
            guard preloadedAssets[asset.localIdentifier] == nil else { continue }
            
            do {
                let avAsset = try await loadAVAsset(for: asset)
                await MainActor.run {
                    preloadedAssets[asset.localIdentifier] = avAsset
                    logger.info("预加载资源成功: \(asset.localIdentifier)")
                }
            } catch {
                await MainActor.run {
                    logger.error("预加载资源失败: \(asset.localIdentifier), 错误: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func prepareToPlay(asset: PHAsset, completion: @escaping (Bool) -> Void) {
        stopAndCleanUp() // 确保在准备新视频之前清理旧的资源
        
        isLoading = true
        currentLoadingTask?.cancel()
        currentLoadingTask = Task {
            do {
                logger.info("Starting to load AVAsset for: \(asset.localIdentifier)")
                let avAsset: AVAsset
                if let preloadedAsset = preloadedAssets[asset.localIdentifier] {
                    avAsset = preloadedAsset
                    logger.info("Using preloaded asset for: \(asset.localIdentifier)")
                } else {
                    avAsset = try await loadAVAsset(for: asset)
                }
                
                let playerItem = AVPlayerItem(asset: avAsset)
                
                await MainActor.run {
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.volume = 1.0
                    self.createPlayerLayer()
                    self.isLoading = false
                    self.logger.info("Player prepared for asset: \(asset.localIdentifier)")
                    self.setupPictureInPicture()
                    completion(true)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.logger.error("Failed to prepare player: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }
    
    private func createPlayerLayer() {
        guard let player = player else { return }
        let newPlayerLayer = AVPlayerLayer(player: player)
        newPlayerLayer.videoGravity = .resizeAspect
        self.playerLayer = newPlayerLayer
    }
    
    private func setupPlayerLayer() {
        guard let player = player, playerLayer == nil else { return }
        let newPlayerLayer = AVPlayerLayer(player: player)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let safeFrame = window.safeAreaLayoutGuide.layoutFrame
            newPlayerLayer.frame = safeFrame
            newPlayerLayer.videoGravity = .resizeAspect
            window.layer.addSublayer(newPlayerLayer)
            self.playerLayer = newPlayerLayer
            // ... 日志输出 ...
        } else {
            self.logger.error("无法将 playerLayer 添加到窗口")
        }
    }
    
    private func loadAVAsset(for asset: PHAsset) async throws -> AVAsset {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let avAsset = avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: NSError(domain: "PlayerViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法加载 AVAsset"]))
                }
            }
        }
    }
    
    func setupPictureInPicture() {
        logger.info("Setting up Picture in Picture")
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.warning("Picture in Picture is not supported on this device")
            pipError = "此设备不支持画中画功能"
            return
        }
        
        guard let playerLayer = self.playerLayer else {
            logger.error("Failed to setup PiP: playerLayer is nil")
            pipError = "无法设置画中画：播放器图层未初始化"
            return
        }
        
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self
        
        // 使用 KVO 观察 PiP 状态变化
        pipPossibleObserver = pipController?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, change in
            self?.isPictureInPicturePossible = change.newValue ?? false
            self?.logger.info("PiP possibility changed: \(self?.isPictureInPicturePossible ?? false)")
        }
        
        pipActiveObserver = pipController?.observe(\.isPictureInPictureActive, options: [.new]) { [weak self] _, change in
            self?.isPictureInPictureActive = change.newValue ?? false
            self?.logger.info("PiP active state changed: \(self?.isPictureInPictureActive ?? false)")
        }
        
        logger.info("Picture in Picture setup completed")
    }
    
    func togglePictureInPicture() {
        guard let pipController = pipController else {
            pipError = "画中画控制器未初始化"
            logger.error("PiP controller is nil")
            return
        }
        
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else if pipController.isPictureInPicturePossible {
            logger.info("Attempting to start PiP")
            pipController.startPictureInPicture()
        } else {
            pipError = "当前无法启动画中画模式，请确保视频正在播放"
            logger.error("PiP is not possible at this time. isPictureInPicturePossible: \(pipController.isPictureInPicturePossible)")
            
            // 检查播放器状态
            if let player = self.player {
                logger.info("Player rate: \(player.rate), status: \(player.status.rawValue)")
                logger.info("Current item status: \(player.currentItem?.status.rawValue ?? -1)")
            } else {
                logger.error("Player is nil")
            }
        }
    }
    
    func stopAndCleanUp() {
        self.logger.info("Stopping player and cleaning up resources")
        self.currentLoadingTask?.cancel()
        self.currentLoadingTask = nil
        self.player?.pause()
        self.player?.replaceCurrentItem(with: nil)
        self.player = nil
        self.pipController?.delegate = nil
        self.pipController = nil
        self.playerLayer?.removeFromSuperlayer()
        self.playerLayer = nil
        self.isLoading = false
    }
    
    func handlePipStateChange(isActive: Bool) {
        DispatchQueue.main.async {
            self.isPipActive = isActive
            if isActive {
                self.logger.info("Picture in Picture started")
            } else {
                self.logger.info("Picture in Picture stopped")
            }
        }
    }
    
    func setPlaybackRate(_ rate: Double) {
        player?.rate = Float(rate)
    }
}

extension PlayerViewModel: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("Will start PiP")
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("Did start PiP")
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("Will stop PiP")
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("Did stop PiP")
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        logger.error("Failed to start PiP: \(error.localizedDescription)")
        pipError = "启动画中画失败：\(error.localizedDescription)"
    }
}