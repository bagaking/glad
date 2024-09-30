import SwiftUI
import Photos
import os
import CloudKit

struct MemoEditorView: View {
    let asset: PHAsset
    @ObservedObject var videoManager: VideoManager
    @State private var memo: String = ""
    @State private var isLoading = true
    @Environment(\.presentationMode) var presentationMode
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var memoSource: MemoSource = .loading
    @State private var showSyncError: Bool = false
    @State private var loadingError: String?

    private enum MemoSource {
        case loading, local, cloud, new
    }
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MemoEditorView")
    
    init(asset: PHAsset, videoManager: VideoManager) {
        self.asset = asset
        self.videoManager = videoManager
        self._memo = State(initialValue: "")
        self._isLoading = State(initialValue: true)
        self._memoSource = State(initialValue: .loading)
        logger.info("MemoEditorView initialized for asset: \(asset.localIdentifier)")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text("Asset ID: \(asset.localIdentifier)")
                    .font(.caption)
                    .padding()
                
                HStack {
                    memoSourceView
                    Spacer()
                }
                .padding(.horizontal)
                
                TextEditor(text: $memo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                    )
                    .padding()
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                    .disabled(isLoading)
                
                if let error = loadingError {
                    Text("加载失败: \(error)")
                        .foregroundColor(.red)
                        .padding()
                }
                
                HStack {
                    Button(action: {
                        // 这里可以添加附加功能，比如添加图片等
                    }) {
                        Image(systemName: "paperclip")
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Button("保存") {
                        saveMemo()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(25)
                }
                .padding()
            }
            .navigationBarTitle("编辑备注", displayMode: .inline)
            .navigationBarItems(leading: Button("取消") {
                presentationMode.wrappedValue.dismiss()
            })
            .alert(isPresented: $showAlert) {
                Alert(title: Text("提示"), message: Text(alertMessage), dismissButton: .default(Text("确定")))
            }
            .overlay(
                Group {
                    if isLoading {
                        ProgressView("加载中...")
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .padding()
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(10)
                            .shadow(radius: 10)
                    }
                }
            )
        }
        .onAppear {
            logger.info("MemoEditorView appeared for asset: \(asset.localIdentifier)")
            loadMemo()
        }
    }
    
    private var memoSourceView: some View {
        HStack {
            Image(systemName: memoSourceIconName)
                .foregroundColor(memoSourceColor)
            Text(memoSourceText)
                .font(.caption)
                .foregroundColor(memoSourceColor)
        }
    }
    
    private var memoSourceIconName: String {
        switch memoSource {
        case .loading: return "hourglass"
        case .local: return "iphone"
        case .cloud: return "icloud"
        case .new: return "plus.circle"
        }
    }
    
    private var memoSourceColor: Color {
        switch memoSource {
        case .loading: return .gray
        case .local: return .green
        case .cloud: return .blue
        case .new: return .orange
        }
    }
    
    private var memoSourceText: String {
        switch memoSource {
        case .loading: return "加载中"
        case .local: return "本地"
        case .cloud: return "云端"
        case .new: return "新建"
        }
    }
    
    private func loadMemo() {
        isLoading = true
        loadingError = nil
        logger.info("开始加载备注 for asset: \(asset.localIdentifier)")
        Task {
            do {
                let (loadedMemo, isFromCloud) = try await videoManager.getMemo(for: asset)
                await MainActor.run {
                    self.memo = loadedMemo
                    self.memoSource = loadedMemo.isEmpty ? .new : (isFromCloud ? .cloud : .local)
                    self.isLoading = false
                    logger.info("成功加载备注: \(loadedMemo.isEmpty ? "空" : "非空"), 来源: \(isFromCloud ? "云端" : "本地")")
                }
            } catch {
                await MainActor.run {
                    handleLoadError(error)
                    self.isLoading = false
                    logger.error("加载备注失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleLoadError(_ error: Error) {
        logger.error("加载备注失败: \(error.localizedDescription)")
        if let ckError = error as? CKError, ckError.code == .networkUnavailable || ckError.code == .networkFailure {
            loadingError = "无法连接到 iCloud，使用本地备注。您可以继续编辑，稍后将自动同步。"
            self.memoSource = .local
        } else {
            loadingError = "加载备注失败: \(error.localizedDescription)"
        }
        
        // 尝试加载本地备注
        if let localMemo = UserDefaults.standard.string(forKey: "LocalMemo_\(asset.localIdentifier)") {
            self.memo = localMemo
        }
        
        // 即使加载失败，也允许用户编辑新的备注
        self.memoSource = .new
    }
    
    private func saveMemo() {
        Task {
            do {
                logger.info("开始保存备注")
                try await videoManager.setMemo(for: asset, memo: memo)
                await MainActor.run {
                    self.memoSource = .cloud
                    self.showSyncError = false
                    logger.info("成功保存备注到云端")
                    showAlertMessage("备注已成功保存到云端")
                }
            } catch {
                await MainActor.run {
                    self.memoSource = .local
                    self.showSyncError = true
                    logger.error("保存备注到云端失败: \(error.localizedDescription)")
                    // 保存到本地
                    UserDefaults.standard.set(self.memo, forKey: "LocalMemo_\(asset.localIdentifier)")
                    showAlertMessage("保存到云端失败：\(error.localizedDescription)\n备注已保存到本地")
                }
            }
        }
    }
    
    private func showAlertMessage(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}