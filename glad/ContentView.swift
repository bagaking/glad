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

struct ContentView: View {
    @StateObject private var videoManager = VideoManager()
    @State private var selectedVideo: PHAsset?
    @State private var isPlayerPresented = false
    @State private var playbackRate: Double = 1.0
    @State private var isPipActive = false
    @State private var gridLayout = [GridItem(.adaptive(minimum: 300))]
    @State private var selectedCategory: VideoCategory = .all
    @State private var isAddingOnlineVideo = false
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ContentView")

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("类别", selection: $selectedCategory) {
                    ForEach(VideoCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top, 8)

                ZStack {
                    Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                    
                    ScrollView {
                        LazyVGrid(columns: gridLayout, spacing: 20) {
                            if selectedCategory == .online {
                                ForEach(videoManager.onlineVideos) { video in
                                    OnlineVideoCard(video: video)
                                }
                            } else {
                                ForEach(filteredVideos, id: \.localIdentifier) { video in
                                    VideoCard(video: video, isFollowed: videoManager.isFollowed(video))
                                        .onTapGesture {
                                            selectedVideo = video
                                            isPlayerPresented = true
                                        }
                                }
                            }
                        }
                        .padding()
                    }
                    .overlay(Group {
                        if filteredVideos.isEmpty && selectedCategory != .online {
                            EmptyStateView()
                        }
                    })
                }
            }
            .navigationTitle("视频库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedCategory == .online {
                        Button(action: {
                            isAddingOnlineVideo = true
                        }) {
                            Image(systemName: "plus")
                        }
                    } else {
                        Button(action: {
                            videoManager.requestAccess()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: {
                            withAnimation {
                                gridLayout = [GridItem(.adaptive(minimum: 300))]
                            }
                        }) {
                            Label("单列", systemImage: "rectangle.grid.1x2")
                        }
                        Button(action: {
                            withAnimation {
                                gridLayout = [GridItem(.adaptive(minimum: 150))]
                            }
                        }) {
                            Label("双列", systemImage: "square.grid.2x2")
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $isAddingOnlineVideo) {
                AddOnlineVideoView(videoManager: videoManager, isPresented: $isAddingOnlineVideo)
            }
            .onAppear {
                videoManager.requestAccess()
                videoManager.loadOnlineVideos()
            }
        }
        .sheet(isPresented: $isPlayerPresented) {
            if let asset = selectedVideo {
                CustomVideoPlayer(asset: asset, playbackRate: $playbackRate, isPipActive: $isPipActive)
            } else {
                Text("无法加载视频")
            }
        }
        .onAppear {
            logger.info("ContentView appeared")
        }
        .onDisappear {
            logger.info("ContentView disappeared")
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
            return [] // 这里需要实现网络内容的获取逻辑
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

struct VideoCard: View {
    let video: PHAsset
    let isFollowed: Bool
    @State private var thumbnail: UIImage?
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray
                }
                LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                    .opacity(isHovered ? 1 : 0)
                Text(formatDuration(video.duration))
                    .font(.caption)
                    .padding(5)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(5)
                    .padding(8)
            }
            .aspectRatio(16/9, contentMode: .fit)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(video.localIdentifier)
                    .font(.headline)
                    .lineLimit(1)
                Text(formatDate(video.creationDate))
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                HStack {
                    Image(systemName: "eye")
                    Text("\(Int.random(in: 100...10000))")
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: isFollowed ? "star.fill" : "star")
                            .foregroundColor(isFollowed ? .yellow : .gray)
                    }
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .shadow(radius: 5)
        .onAppear {
            loadThumbnail()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        option.version = .current
        option.deliveryMode = .fastFormat
        
        manager.requestImage(for: video, targetSize: CGSize(width: 300, height: 169), contentMode: .aspectFill, options: option) { image, _ in
            self.thumbnail = image
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
