//
//  ContentView.swift
//  glad
//
//  Created by bytedance on 9/28/24.
//

import SwiftUI
import Photos
import AVKit
import os
import CoreLocation
import CloudKit
import Network

struct ContentView: View {
    @StateObject private var videoManager = VideoManager()
    @State private var selectedVideo: PHAsset?
    @State private var isPlayerPresented = false
    @State private var playbackRate: Double = 1.0
    @State private var isPipActive = false
    @State private var selectedCategory: VideoCategory = .all
    @State private var isAddingOnlineVideo = false
    @StateObject private var playerViewModel = PlayerViewModel()
    @State private var selectedVideoForMemo: PHAsset?
    @State private var isShowingMemoEditor = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isCardView = false
    @State private var isPlayerReady = false
    @State private var showNetworkError = false
    @EnvironmentObject var networkMonitor: NetworkMonitor
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ContentView")

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !networkMonitor.isConnected {
                    Text("网络连接已断开")
                        .foregroundColor(.red)
                        .padding()
                        .background(Color(UIColor.systemBackground))
                }
                categoryPicker
                videoGrid
            }
            .navigationTitle("视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { addOrRefreshButton }
                ToolbarItem(placement: .navigationBarLeading) {
                    if videoManager.isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    } else {
                        Button(action: { 
                            Task {
                                await videoManager.syncMemos()
                            }
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddingOnlineVideo) {
                AddOnlineVideoView(videoManager: videoManager, isPresented: $isAddingOnlineVideo)
            }
            .sheet(isPresented: $isPlayerPresented) {
                if isPlayerReady, let asset = selectedVideo {
                    CustomVideoPlayer(
                        asset: asset,
                        playerViewModel: playerViewModel,
                        onVideoPlay: { playedAsset in
                            videoManager.addToRecentlyWatched(playedAsset)
                        },
                        playbackRate: $playbackRate,
                        isPipActive: $isPipActive
                    )
                } else {
                    ProgressView("正在准备视频...")
                }
            }
            .sheet(isPresented: $isShowingMemoEditor) {
                if let asset = selectedVideoForMemo {
                    MemoEditorView(asset: asset, videoManager: videoManager)
                } else {
                    Text("No video selected")
                }
            }
            .onAppear {
                videoManager.requestAccess()
                videoManager.loadOnlineVideos()
                logger.info("ContentView appeared")
                Task {
                    await preloadVideos()
                }
            }
            .onDisappear {
                logger.info("ContentView disappeared")
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("提示"), message: Text(alertMessage), dismissButton: .default(Text("确定")))
            }
            .alert(isPresented: $showNetworkError) {
                Alert(
                    title: Text("网络错误"),
                    message: Text("无法连接到 iCloud。请检查您的网络连接，然后重试。"),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
    }
    
    private var categoryPicker: some View {
        Picker("类别", selection: $selectedCategory) {
            ForEach(VideoCategory.allCases, id: \.self) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
        .padding(.vertical, 8)  // 增加垂直方向的内边距
        .background(Color(UIColor.secondarySystemBackground))  // 添加背景色
    }
    
    private var videoGrid: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // 添加一个空的视图来创建顶部间距
                Color.clear.frame(height: 16)
                
                if selectedCategory == .online {
                    ForEach(videoManager.onlineVideos) { video in
                        OnlineVideoCard(video: video)
                    }
                } else {
                    ForEach(filteredVideos, id: \.localIdentifier) { video in
                        if isCardView {
                            VideoCardView(video: video, isFollowed: videoManager.isFollowed(video), videoManager: videoManager, selectedVideoForMemo: $selectedVideoForMemo, isShowingMemoEditor: $isShowingMemoEditor)
                                .onTapGesture {
                                    prepareAndPlayVideo(video)
                                }
                        } else {
                            VideoListItemView(video: video, isFollowed: videoManager.isFollowed(video), videoManager: videoManager, selectedVideoForMemo: $selectedVideoForMemo, isShowingMemoEditor: $isShowingMemoEditor)
                                .onTapGesture {
                                    prepareAndPlayVideo(video)
                                }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var addOrRefreshButton: some View {
        Group {
            if selectedCategory == .online {
                Button(action: { isAddingOnlineVideo = true }) {
                    Image(systemName: "plus")
                }
            } else {
                Button(action: { videoManager.requestAccess() }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
    
    var filteredVideos: [PHAsset] {
        switch selectedCategory {
        case .all:
            return videoManager.videos
        case .recentlyWatched:
            return videoManager.recentlyWatchedVideos
        case .favorites:
            return videoManager.videos.filter { videoManager.isFollowed($0) }
        case .online:
            return [] // 这需要实现网络内容的获取逻辑
        }
    }
    
    private func showAlertMessage(_ message: String) {
        alertMessage = message
        showAlert = true
    }
    
    private func preloadVideos() async {
        let preloadCount = min(filteredVideos.count, 5) // 预加载前5个视频
        
        for video in filteredVideos.prefix(preloadCount) {
            do {
                try await playerViewModel.preloadAssets([video])
                try await preloadMemo(for: video)
                logger.info("Successfully preloaded video and memo for asset: \(video.localIdentifier)")
            } catch {
                logger.error("Failed to preload video or memo for asset: \(video.localIdentifier), error: \(error.localizedDescription)")
            }
        }
    }
    
    private func preloadMemo(for video: PHAsset) async throws {
        do {
            let (memo, _) = try await videoManager.getMemo(for: video)
            logger.info("Preloaded memo for asset: \(video.localIdentifier), memo length: \(memo.count)")
        } catch {
            logger.error("Failed to preload memo for asset: \(video.localIdentifier), error: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func prepareAndPlayVideo(_ video: PHAsset) {
        isPlayerReady = false
        selectedVideo = video
        isPlayerPresented = true // 立即显示加载界面
        Task {
            await playerViewModel.prepareToPlay(asset: video) { success in
                if success {
                    isPlayerReady = true
                } else {
                    // 处理准备失败的情况
                    isPlayerPresented = false
                    showAlertMessage("视频准备失败，请重试。")
                }
            }
        }
    }
}

enum VideoCategory: String, CaseIterable {
    case all = "全部"
    case recentlyWatched = "最近观看"
    case favorites = "收藏列表"
    case online = "网络内容"
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            Text("没有找到视频")
                .font(.title)
                .foregroundColor(.gray)
        }
    }
}

struct VideoCardView: View {
    let video: PHAsset
    let isFollowed: Bool
    @ObservedObject var videoManager: VideoManager
    @Binding var selectedVideoForMemo: PHAsset?
    @Binding var isShowingMemoEditor: Bool
    @State private var thumbnail: UIImage?
    @State private var isCloudAsset: Bool = false
    @State private var isLoading: Bool = false
    @State private var locationInfo: String = ""
    @State private var memoPreview: String = ""
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VideoCard")
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧缩略图
            thumbnailView
            
            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                Text(video.localIdentifier)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text(formatDate(video.creationDate))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                if !locationInfo.isEmpty {
                    Text(locationInfo)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                if !memoPreview.isEmpty {
                    Text(memoPreview)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button(action: {
                        selectedVideoForMemo = video
                        isShowingMemoEditor = true
                    }) {
                        Image(systemName: "note.text")
                            .foregroundColor(.blue)
                    }
                    Button(action: {
                        videoManager.toggleFollow(video)
                    }) {
                        Image(systemName: isFollowed ? "star.fill" : "star")
                            .foregroundColor(isFollowed ? .yellow : .gray)
                    }
                }
            }
        }
        .frame(height: 100)  // 增加高度以容纳更多内容
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .onAppear {
            logger.info("Loading thumbnail for video: \(video.localIdentifier)")
            isLoading = true
            loadThumbnail()
            checkCloudStatus()
            getLocationInfo()
            loadMemoPreview()
        }
    }
    
    private var thumbnailView: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 80)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .frame(width: 120, height: 80)
            } else {
                Color.gray
                    .frame(width: 120, height: 80)
            }
            
            VStack {
                Spacer()
                HStack {
                    if isCloudAsset {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                    Spacer()
                    Text(formatDuration(video.duration))
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                .padding(4)
            }
        }
        .frame(width: 120, height: 80)
        .cornerRadius(8)
    }
    
    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        option.version = .current
        option.deliveryMode = .fastFormat
        
        let targetSize = CGSize(width: 240, height: 160) // 2倍大小以适应 Retina 显示器
        
        manager.requestImage(for: video, targetSize: targetSize, contentMode: .aspectFill, options: option) { image, _ in
            DispatchQueue.main.async {
                self.thumbnail = image
                self.isLoading = false
                self.logger.info("Thumbnail loaded for video: \(self.video.localIdentifier)")
            }
        }
    }
    
    private func checkCloudStatus() {
        PHImageManager.default().requestImageDataAndOrientation(for: video, options: nil) { (_, _, _, info) in
            if let isCloudPlaceholder = info?[PHImageResultIsInCloudKey] as? Bool {
                self.isCloudAsset = isCloudPlaceholder
                self.logger.info("Cloud status for video \(self.video.localIdentifier): \(isCloudPlaceholder)")
            }
        }
    }
    
    private func getLocationInfo() {
        if let location = video.location {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let placemark = placemarks?.first {
                    if let city = placemark.locality {
                        self.locationInfo = "拍摄于 \(city)"
                    } else if let country = placemark.country {
                        self.locationInfo = "拍摄于 \(country)"
                    }
                }
            }
        } else {
            // 尝试获取视频源信息
            let resources = PHAssetResource.assetResources(for: video)
            if let resource = resources.first {
                self.locationInfo = "来自 \(getAppName(filename: resource.originalFilename, uniformTypeIdentifier: resource.uniformTypeIdentifier))"
            }
        }
    }
    
    private func getAppName(filename: String, uniformTypeIdentifier: String) -> String {
        let knownPrefixes = [
            "IMG_": "相机",
            "MOV_": "相机",
            "IG_": "Instagram",
            "TikTok_": "TikTok",
            "FB_": "Facebook",
            "Twitter_": "Twitter",
            "YT_": "YouTube",
        ]
        
        // 检查文件名前缀
        for (prefix, appName) in knownPrefixes {
            if filename.hasPrefix(prefix) {
                return appName
            }
        }
        
        // 检查是否为复制的文件
        if filename.contains("副本") || filename.contains("Copy") {
            return "复制的文件"
        }
        
        // 如果文件名没有匹配，检查 uniformTypeIdentifier
        switch uniformTypeIdentifier {
        case "com.apple.quicktime-movie":
            return "相机"
        case "public.mpeg-4":
            return "相机"
        case "com.apple.m4v-video":
            return "iTunes"
        // 可以添加更多的类型标识符
        default:
            return "其他应用"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? ""
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "未知日期" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func loadMemoPreview() {
        if let memo = videoManager.videoMemos[video.localIdentifier], !memo.isEmpty {
            memoPreview = String(memo.prefix(50)) + (memo.count > 50 ? "..." : "")
        }
    }
}

struct VideoListItemView: View {
    let video: PHAsset
    let isFollowed: Bool
    @ObservedObject var videoManager: VideoManager
    @Binding var selectedVideoForMemo: PHAsset?
    @Binding var isShowingMemoEditor: Bool
    @State private var thumbnail: UIImage?
    @State private var isCloudAsset: Bool = false
    @State private var isLoading: Bool = false
    @State private var locationInfo: String = ""
    @State private var memoPreview: String = ""
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VideoListItem")
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧缩略图
            thumbnailView
            
            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                Text(video.localIdentifier)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text(formatDate(video.creationDate))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                if !locationInfo.isEmpty {
                    Text(locationInfo)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                if !memoPreview.isEmpty {
                    Text(memoPreview)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button(action: {
                        selectedVideoForMemo = video
                        isShowingMemoEditor = true
                    }) {
                        Image(systemName: "note.text")
                            .foregroundColor(.blue)
                    }
                    Button(action: {
                        videoManager.toggleFollow(video)
                    }) {
                        Image(systemName: isFollowed ? "star.fill" : "star")
                            .foregroundColor(isFollowed ? .yellow : .gray)
                    }
                }
            }
        }
        .frame(height: 100)  // 增加高度以容纳更多内容
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .onAppear {
            logger.info("Loading thumbnail for video: \(video.localIdentifier)")
            isLoading = true
            loadThumbnail()
            checkCloudStatus()
            getLocationInfo()
            loadMemoPreview()
        }
    }
    
    private var thumbnailView: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 80)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .frame(width: 120, height: 80)
            } else {
                Color.gray
                    .frame(width: 120, height: 80)
            }
            
            VStack {
                Spacer()
                HStack {
                    if isCloudAsset {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                    Spacer()
                    Text(formatDuration(video.duration))
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                .padding(4)
            }
        }
        .frame(width: 120, height: 80)
        .cornerRadius(8)
    }
    
    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        option.version = .current
        option.deliveryMode = .fastFormat
        
        let targetSize = CGSize(width: 240, height: 160) // 2倍大小以适应 Retina 显示器
        
        manager.requestImage(for: video, targetSize: targetSize, contentMode: .aspectFill, options: option) { image, _ in
            DispatchQueue.main.async {
                self.thumbnail = image
                self.isLoading = false
                self.logger.info("Thumbnail loaded for video: \(self.video.localIdentifier)")
            }
        }
    }
    
    private func checkCloudStatus() {
        PHImageManager.default().requestImageDataAndOrientation(for: video, options: nil) { (_, _, _, info) in
            if let isCloudPlaceholder = info?[PHImageResultIsInCloudKey] as? Bool {
                self.isCloudAsset = isCloudPlaceholder
                self.logger.info("Cloud status for video \(self.video.localIdentifier): \(isCloudPlaceholder)")
            }
        }
    }
    
    private func getLocationInfo() {
        if let location = video.location {
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let placemark = placemarks?.first {
                    if let city = placemark.locality {
                        self.locationInfo = "拍摄于 \(city)"
                    } else if let country = placemark.country {
                        self.locationInfo = "拍摄于 \(country)"
                    }
                }
            }
        } else {
            // 尝试获取视频源信息
            let resources = PHAssetResource.assetResources(for: video)
            if let resource = resources.first {
                self.locationInfo = "来自 \(getAppName(filename: resource.originalFilename, uniformTypeIdentifier: resource.uniformTypeIdentifier))"
            }
        }
    }
    
    private func getAppName(filename: String, uniformTypeIdentifier: String) -> String {
        let knownPrefixes = [
            "IMG_": "相机",
            "MOV_": "相机",
            "IG_": "Instagram",
            "TikTok_": "TikTok",
            "FB_": "Facebook",
            "Twitter_": "Twitter",
            "YT_": "YouTube",
        ]
        
        // 检查文件名前缀
        for (prefix, appName) in knownPrefixes {
            if filename.hasPrefix(prefix) {
                return appName
            }
        }
        
        // 检查是否为复制的文件
        if filename.contains("副本") || filename.contains("Copy") {
            return "复制的文件"
        }
        
        // 如果文件名没有匹配，检查 uniformTypeIdentifier
        switch uniformTypeIdentifier {
        case "com.apple.quicktime-movie":
            return "相机"
        case "public.mpeg-4":
            return "相机"
        case "com.apple.m4v-video":
            return "iTunes"
        // 可以添加更多的类型标识符
        default:
            return "其他应用"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? ""
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "未知日期" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func loadMemoPreview() {
        if let memo = videoManager.videoMemos[video.localIdentifier], !memo.isEmpty {
            memoPreview = String(memo.prefix(50)) + (memo.count > 50 ? "..." : "")
        }
    }
}

struct OnlineVideoCard: View {
    let video: OnlineVideo
    
    var body: some View {
        Link(destination: video.videoURL) {
            VStack(alignment: .leading, spacing: 8) {
                Color.gray // 占位图
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                    )
                
                Text(video.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(video.videoURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(height: 200)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .shadow(radius: 5)
        }
    }
}

struct AddOnlineVideoView: View {
    @ObservedObject var videoManager: VideoManager
    @Binding var isPresented: Bool
    @State private var url = ""
    @State private var title = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("视频信息")) {
                    TextField("视频标题", text: $title)
                    TextField("视频URL", text: $url)
                }
            }
            .navigationTitle("添加网络视频")
            .navigationBarItems(
                leading: Button("取消") { isPresented = false },
                trailing: Button("保存") {
                    videoManager.addOnlineVideo(url: url, title: title)
                    isPresented = false
                }
                .disabled(url.isEmpty || title.isEmpty)
            )
        }
    }
}

#Preview {
    ContentView()
}