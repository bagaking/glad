import SwiftUI
import Photos
import os

class VideoManager: ObservableObject {
    @Published var videos: [PHAsset] = []
    @Published var followedVideos: Set<String> = []
    @Published var recentlyWatchedVideos: [PHAsset] = []
    @Published var onlineVideos: [OnlineVideo] = []
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VideoManager")
    
    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .authorized, .limited:
                self.fetchVideos()
            case .denied, .restricted:
                DispatchQueue.main.async {
                    self.logger.error("Photo library access denied or restricted")
                }
            case .notDetermined:
                self.logger.info("Photo library access not determined")
            @unknown default:
                self.logger.error("Unknown photo library access status")
            }
        }
    }
    
    private func fetchVideos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allVideos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.videos = allVideos.objects(at: IndexSet(0..<allVideos.count))
            self.sortVideos()
            self.logger.info("Fetched \(self.videos.count) videos")
        }
    }
    
    func toggleFollow(_ video: PHAsset) {
        if followedVideos.contains(video.localIdentifier) {
            followedVideos.remove(video.localIdentifier)
        } else {
            followedVideos.insert(video.localIdentifier)
        }
        sortVideos()
    }
    
    func isFollowed(_ video: PHAsset) -> Bool {
        followedVideos.contains(video.localIdentifier)
    }
    
    private func sortVideos() {
        videos.sort { (video1, video2) -> Bool in
            let isFollowed1 = followedVideos.contains(video1.localIdentifier)
            let isFollowed2 = followedVideos.contains(video2.localIdentifier)
            
            if isFollowed1 == isFollowed2 {
                return video1.creationDate ?? Date() > video2.creationDate ?? Date()
            }
            return isFollowed1 && !isFollowed2
        }
    }
    
    func addToRecentlyWatched(_ video: PHAsset) {
        if let index = recentlyWatchedVideos.firstIndex(of: video) {
            recentlyWatchedVideos.remove(at: index)
        }
        recentlyWatchedVideos.insert(video, at: 0)
        if recentlyWatchedVideos.count > 20 {  // 限制最近观看列表的大小
            recentlyWatchedVideos.removeLast()
        }
    }
    
    func fetchOnlineVideos() {
        // 实现从网络获取视频的逻辑
        // 这可能涉及到网络请求、数据解析等
        // 获取到数据后，更新 onlineVideos 数组
    }
    
    func addOnlineVideo(url: String, title: String) {
        guard let videoURL = URL(string: url) else {
            logger.error("Invalid URL: \(url)")
            return
        }
        
        let newVideo = OnlineVideo(id: UUID().uuidString, title: title, videoURL: videoURL)
        onlineVideos.append(newVideo)
        saveOnlineVideos()
        logger.info("Added online video: \(title)")
    }
    
    func removeOnlineVideo(id: String) {
        onlineVideos.removeAll { $0.id == id }
        saveOnlineVideos()
        logger.info("Removed online video with id: \(id)")
    }
    
    private func saveOnlineVideos() {
        // 将 onlineVideos 保存到 UserDefaults 或其他持久化存储
        let videosData = onlineVideos.map { ["id": $0.id, "title": $0.title, "url": $0.videoURL.absoluteString] }
        UserDefaults.standard.set(videosData, forKey: "OnlineVideos")
    }
    
    func loadOnlineVideos() {
        guard let videosData = UserDefaults.standard.array(forKey: "OnlineVideos") as? [[String: String]] else {
            return
        }
        
        onlineVideos = videosData.compactMap { data in
            guard let id = data["id"],
                  let title = data["title"],
                  let urlString = data["url"],
                  let url = URL(string: urlString) else {
                return nil
            }
            return OnlineVideo(id: id, title: title, videoURL: url)
        }
        logger.info("Loaded \(self.onlineVideos.count) online videos")
    }
}

struct OnlineVideo: Identifiable {
    let id: String
    let title: String
    let videoURL: URL
    // 其他需要的属性
}
