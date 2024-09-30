import Foundation
import CloudKit
import os

class MemoManager {
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MemoManager")
    private let userDefaults = UserDefaults.standard
    
    init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase
        logger.info("Initialized CKContainer and database")
    }
    
    func saveMemo(for videoID: String, memo: String) async throws {
        saveLocalMemo(for: videoID, memo: memo)
        
        let record = CKRecord(recordType: "VideoMemo")
        record["videoID"] = videoID
        record["memo"] = memo
        
        do {
            try await privateDatabase.save(record)
            logger.info("成功保存备注到 iCloud: \(memo) 为视频: \(videoID)")
        } catch let error as CKError {
            logger.error("保存备注到 iCloud 失败: \(error.localizedDescription)")
            throw handleCloudKitError(error)
        }
    }
    
    func fetchMemo(for videoID: String) async throws -> String {
        if let localMemo = getLocalMemo(for: videoID) {
            return localMemo
        }
        
        let predicate = NSPredicate(format: "videoID == %@", videoID)
        let query = CKQuery(recordType: "VideoMemo", predicate: predicate)
        
        do {
            let (matchResults, _) = try await privateDatabase.records(matching: query, inZoneWith: nil)
            for (_, recordResult) in matchResults {
                switch recordResult {
                case .success(let record):
                    if let memo = record["memo"] as? String {
                        saveLocalMemo(for: videoID, memo: memo)
                        return memo
                    }
                case .failure(let error):
                    logger.error("获取记录失败: \(error.localizedDescription)")
                }
            }
            return ""
        } catch let error as CKError {
            logger.error("从 iCloud 获取备注失败: \(error.localizedDescription)")
            throw handleCloudKitError(error)
        }
    }
    
    func saveMemosBatch(_ memos: [(videoID: String, memo: String)]) async throws {
        let records = memos.map { memo -> CKRecord in
            let record = CKRecord(recordType: "VideoMemo")
            record["videoID"] = memo.videoID
            record["memo"] = memo.memo
            return record
        }
        
        do {
            let (savedResults, _) = try await privateDatabase.modifyRecords(saving: records, deleting: [])
            for (_, saveResult) in savedResults {
                switch saveResult {
                case .success(let record):
                    if let videoID = record["videoID"] as? String, let memo = record["memo"] as? String {
                        saveLocalMemo(for: videoID, memo: memo)
                        logger.info("成功保存备注到 iCloud: \(memo) 为视频: \(videoID)")
                    }
                case .failure(let error):
                    logger.error("保存备注到 iCloud 失败: \(error.localizedDescription)")
                }
            }
        } catch let error as CKError {
            logger.error("批量保存备注到 iCloud 失败: \(error.localizedDescription)")
            throw handleCloudKitError(error)
        }
    }
    
    private func handleCloudKitError(_ error: CKError) -> Error {
        switch error.code {
        case .networkFailure, .networkUnavailable:
            return NSError(domain: "MemoManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "网络连接失败，请检查您的网络设置。"])
        case .quotaExceeded:
            return NSError(domain: "MemoManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud 存储空间已满，请清理一些空间。"])
        case .serverResponseLost:
            return NSError(domain: "MemoManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "服务器响应丢失，请稍后重试。"])
        default:
            return error
        }
    }
    
    private func saveLocalMemo(for videoID: String, memo: String) {
        var memos = userDefaults.dictionary(forKey: "LocalMemos") as? [String: String] ?? [:]
        memos[videoID] = memo
        userDefaults.set(memos, forKey: "LocalMemos")
    }
    
    private func getLocalMemo(for videoID: String) -> String? {
        let memos = userDefaults.dictionary(forKey: "LocalMemos") as? [String: String] ?? [:]
        return memos[videoID]
    }
}
