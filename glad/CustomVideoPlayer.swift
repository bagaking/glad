import SwiftUI
import AVKit
import Photos
import os
import AVFoundation

struct CustomVideoPlayer: View {
    let asset: PHAsset
    @ObservedObject var playerViewModel: PlayerViewModel
    let onVideoPlay: (PHAsset) -> Void
    @Binding var playbackRate: Double
    @Binding var isPipActive: Bool
    @State private var showPipError = false
    @Environment(\.presentationMode) var presentationMode
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CustomVideoPlayer")
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    videoPlayerView
                        .frame(height: geometry.size.height - 100)
                    
                    controlPanel
                        .frame(height: 100)
                }
                
                if showPipError {
                    Text(playerViewModel.pipError ?? "未知错误")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            logger.info("CustomVideoPlayer appeared for asset: \(asset.localIdentifier)")
            setupPlayer()
        }
        .onDisappear {
            logger.info("CustomVideoPlayer disappeared for asset: \(asset.localIdentifier)")
            playerViewModel.stopAndCleanUp()
        }
        .onChange(of: playbackRate) { newRate in
            playerViewModel.player?.rate = Float(newRate)
        }
        .onChange(of: playerViewModel.pipError) { error in
            if error != nil {
                showPipError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showPipError = false
                    playerViewModel.pipError = nil
                }
            }
        }
    }
    
    private func setupPlayer() {
        playerViewModel.prepareToPlay(asset: asset) { success in
            if success {
                logger.info("Player prepared successfully, starting playback")
                playerViewModel.player?.play()
                onVideoPlay(asset)
                playerViewModel.setupPictureInPicture()
            } else {
                logger.error("Failed to prepare player")
            }
        }
    }
    
    private var videoPlayerView: some View {
        Group {
            if playerViewModel.isLoading {
                ProgressView("正在加载视频...")
                    .foregroundColor(.white)
            } else if let player = playerViewModel.player {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fit)
                    .overlay(Color.clear)
            } else {
                Text("播放器初始化失败")
                    .foregroundColor(.white)
            }
        }
    }
    
    private var controlPanel: some View {
        VStack(spacing: 20) {
            if let player = playerViewModel.player {
                CustomVideoProgressView(player: player)
            }
            
            HStack {
                dismissButton
                Spacer()
                playbackSpeedButton
                Spacer()
                pipButton
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 30)
        .background(Color.black.opacity(0.7))
    }
    
    private var dismissButton: some View {
        Button(action: {
            logger.info("Dismiss button tapped")
            playerViewModel.stopAndCleanUp()
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "xmark")
                .font(.title2)
                .foregroundColor(.white)
        }
        .buttonStyle(CircleButtonStyle())
    }
    
    private var playbackSpeedButton: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button(action: {
                    playbackRate = rate
                }) {
                    Text("\(rate, specifier: "%.2f")x")
                }
            }
        } label: {
            Text("\(playbackRate, specifier: "%.2f")x")
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
    }
    
    private var pipButton: some View {
        Button(action: {
            logger.info("Picture in Picture button tapped")
            playerViewModel.togglePictureInPicture()
        }) {
            Image(systemName: playerViewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                .font(.title2)
                .foregroundColor(.white)
        }
        .buttonStyle(CircleButtonStyle())
        .disabled(!playerViewModel.isPictureInPicturePossible)
        .opacity(playerViewModel.isPictureInPicturePossible ? 1.0 : 0.5)
    }
}

struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.2))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
    }
}

