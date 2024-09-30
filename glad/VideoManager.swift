import SwiftUI
import Photos
import os
import CloudKit

class VideoManager: ObservableObject {
    @Published var videos: [PHAsset] = []
    @Published var followedVideos: Set<String> = []
    @Published var recentlyWatchedVideos: [PHAsset] = []
    @Published var onlineVideos: [OnlineVideo] = []
    @Published var videoMemos: [String: String] = [:] // 存储视频注释
    @Published var isSyncing: Bool = false // 新增：同步状态
    @Published var memoSources: [String: Bool] = [:] // true 表示来自云端，false 表示本地

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VideoManager")
    private let memoManager = MemoManager()
    private let retryLimit = 3
    private let retryDelay: TimeInterval = 2.0
    private var syncTimer: Timer?
    
    // MARK: - Public Methods
    
    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard let self = self else { return }
            self.handleAuthorizationStatus(status)
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
    
    func addToRecentlyWatched(_ video: PHAsset) {
        if let index = recentlyWatchedVideos.firstIndex(of: video) {
            recentlyWatchedVideos.remove(at: index)
        }
        recentlyWatchedVideos.insert(video, at: 0)
        if recentlyWatchedVideos.count > 20 {  // 限制最近观看列表的大小
            recentlyWatchedVideos.removeLast()
        }
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
    
    func checkVideoAvailability(_ asset: PHAsset, completion: @escaping (Result<Void, Error>) -> Void) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .video }) else {
            completion(.failure(NSError(domain: "VideoManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "找不到视频资源"])))
            return
        }
        
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().requestData(for: videoResource, options: options) { data in
            DispatchQueue.main.async {
                if data.isEmpty {
                    completion(.failure(NSError(domain: "VideoManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "视频数据为空"])))
                } else {
                    completion(.success(()))
                }
            }
        } completionHandler: { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    func getMemo(for video: PHAsset) async throws -> (String, Bool) {
        logger.info("Getting memo for asset: \(video.localIdentifier)")
        do {
            let (memo, isFromCloud) = try await memoManager.fetchMemo(for: video.localIdentifier)
            await MainActor.run {
                self.videoMemos[video.localIdentifier] = memo
                self.memoSources[video.localIdentifier] = isFromCloud
            }
            logger.info("Successfully fetched memo for asset: \(video.localIdentifier)")
            return (memo, isFromCloud)
        } catch {
            logger.error("Failed to fetch memo from iCloud for asset: \(video.localIdentifier), error: \(error.localizedDescription)")
            // 如果 iCloud 获取失败，尝试返回本地备注
            if let localMemo = UserDefaults.standard.string(forKey: "LocalMemo_\(video.localIdentifier)") {
                await MainActor.run {
                    self.videoMemos[video.localIdentifier] = localMemo
                    self.memoSources[video.localIdentifier] = false
                }
                logger.info("Returned local memo for asset: \(video.localIdentifier)")
                return (localMemo, false)
            }
            throw error
        }
    }
    
    func setMemo(for video: PHAsset, memo: String) async throws {
        // 先保存到本地
        UserDefaults.standard.set(memo, forKey: "LocalMemo_\(video.localIdentifier)")
        
        do {
            try await memoManager.saveMemo(for: video.localIdentifier, memo: memo)
            await MainActor.run {
                self.videoMemos[video.localIdentifier] = memo
                self.memoSources[video.localIdentifier] = true // 标记为云端来源
            }
            logger.info("成功保存备注到云端: \(video.localIdentifier)")
        } catch {
            logger.error("保存备注到云端失败: \(error.localizedDescription)")
            if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                throw NSError(domain: "VideoManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "iCloud 服务暂时不可用，请稍后重试。备注已保存到本地。"])
            } else {
                throw error
            }
        }
    }
    
    func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.syncMemos()
        }
    }
    
    func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    func syncMemos() {
        Task {
            await MainActor.run { self.isSyncing = true }
            
            for (videoID, memo) in videoMemos {
                do {
                    try await memoManager.saveMemo(for: videoID, memo: memo)
                    logger.info("同步备注成功: \(videoID)")
                } catch {
                    logger.error("同步备注失败: \(videoID), 错误: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run { self.isSyncing = false }
        }
    }
    
    // MARK: - Private Methods
    
    private func handleAuthorizationStatus(_ status: PHAuthorizationStatus) {
        DispatchQueue.main.async {
            switch status {
            case .authorized, .limited:
                self.fetchVideos()
            case .denied, .restricted:
                self.logger.error("Photo library access denied or restricted")
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
        
        self.videos = allVideos.objects(at: IndexSet(0..<allVideos.count))
        sortVideos()
        logger.info("Fetched \(self.videos.count) videos")
        loadMemos()
    }
    
    private func sortVideos() {
        self.videos.sort { (video1, video2) -> Bool in
            let isFollowed1 = self.followedVideos.contains(video1.localIdentifier)
            let isFollowed2 = self.followedVideos.contains(video2.localIdentifier)
            
            if isFollowed1 == isFollowed2 {
                return video1.creationDate ?? Date() > video2.creationDate ?? Date()
            }
            return isFollowed1 && !isFollowed2
        }
    }
    
    private func saveOnlineVideos() {
        let videosData = onlineVideos.map { ["id": $0.id, "title": $0.title, "url": $0.videoURL.absoluteString] }
        UserDefaults.standard.set(videosData, forKey: "OnlineVideos")
    }
    
    private func saveMemos() {
        if let encoded = try? JSONEncoder().encode(self.videoMemos) {
            UserDefaults.standard.set(encoded, forKey: "VideoMemos")
            self.logger.info("保存备注到 UserDefaults")
        }
    }
    
    private func loadMemos() {
        if let savedMemos = UserDefaults.standard.object(forKey: "VideoMemos") as? Data {
            if let decodedMemos = try? JSONDecoder().decode([String: String].self, from: savedMemos) {
                self.videoMemos = decodedMemos
                self.logger.info("从 UserDefaults 加载备注: \(self.videoMemos.count) 条")
            }
        }
    }
    
    init() {
        loadMemos()
        startSyncTimer()
    }
    
    deinit {
        stopSyncTimer()
    }
}

struct OnlineVideo: Identifiable {
    let id: String
    let title: String
    let videoURL: URL
}