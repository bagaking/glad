import SwiftUI
import AVKit
import Photos
import os

struct CustomVideoPlayer: View {
    let asset: PHAsset
    @Binding var playbackRate: Double
    @Binding var isPipActive: Bool
    @State private var player: AVPlayer?
    @State private var pipController: AVPictureInPictureController?
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CustomVideoPlayer")
    
    var body: some View {
        VStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        setupPictureInPicture()
                    }
            } else {
                ProgressView()
            }
            
            Slider(value: $playbackRate, in: 0.5...2.0, step: 0.1)
                .padding()
            
            Text("播放速度: \(playbackRate, specifier: "%.1f")x")
            
            Button(action: {
                pipController?.startPictureInPicture()
            }) {
                Text("开启画中画")
            }
            .disabled(pipController == nil)
        }
        .onAppear {
            loadVideoAsset()
        }
        .onChange(of: playbackRate) { _, newRate in
            player?.rate = Float(newRate)
        }
    }
    
    private func loadVideoAsset() {
        PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { (avAsset, _, _) in
            if let avAsset = avAsset {
                DispatchQueue.main.async {
                    let playerItem = AVPlayerItem(asset: avAsset)
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.play()
                    self.logger.info("Video asset loaded successfully")
                }
            } else {
                self.logger.error("Failed to load video asset")
            }
        }
    }
    
    private func setupPictureInPicture() {
        guard let player = player,
              AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.warning("Picture in Picture not supported")
            return
        }
        
        pipController = AVPictureInPictureController(playerLayer: AVPlayerLayer(player: player))
        pipController?.delegate = PipDelegate(isPipActive: $isPipActive)
        logger.info("Picture in Picture setup completed")
    }
}

class PipDelegate: NSObject, AVPictureInPictureControllerDelegate {
    @Binding var isPipActive: Bool
    
    init(isPipActive: Binding<Bool>) {
        _isPipActive = isPipActive
    }
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPipActive = true
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPipActive = false
    }
}