import SwiftUI
import AVKit


struct CustomVideoProgressView: View {
    let player: AVPlayer
    @State private var progress: Double = 0
    @State private var isEditing = false
    @State private var duration: Double = 0
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 8) {
            Slider(value: $progress, in: 0...1, onEditingChanged: { editing in
                isEditing = editing
                if !editing {
                    let targetTime = progress * duration
                    player.seek(to: CMTime(seconds: targetTime, preferredTimescale: 600))
                }
            })
            .accentColor(.white)
            
            HStack {
                Text(formatTime(progress * duration))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption)
            .foregroundColor(.white)
        }
        .onReceive(timer) { _ in
            guard let currentItem = player.currentItem, !isEditing else { return }
            let currentTime = CMTimeGetSeconds(player.currentTime())
            duration = CMTimeGetSeconds(currentItem.duration)
            progress = currentTime / duration
        }
        .onAppear {
            if let currentItem = player.currentItem {
                duration = CMTimeGetSeconds(currentItem.duration)
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
