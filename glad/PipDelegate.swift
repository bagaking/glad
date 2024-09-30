import SwiftUI
import AVKit
import Photos
import os
import AVFoundation

class PipDelegate: NSObject, AVPictureInPictureControllerDelegate {
    private let viewModel: PlayerViewModel
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PipDelegate")
    
    init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("PiP will start")
        viewModel.handlePipStateChange(isActive: true)
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("PiP did start successfully")
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        logger.error("Failed to start PiP: \(error.localizedDescription)")
        if let avError = error as? AVError {
            logger.error("AVError code: \(avError.code.rawValue)")
            logger.error("AVError description: \(avError.localizedDescription)")
            
            // 更新错误处理逻辑
            switch avError.code {
            case .contentIsProtected:
                logger.error("Content is protected and cannot be played in PiP")
            case .mediaServicesWereReset:
                logger.error("Media services were reset")
            case .noLongerPlayable:
                logger.error("Content is no longer playable")
            case .operationNotAllowed:
                logger.error("Operation not allowed")
            default:
                logger.error("Unknown AVError code: \(avError.code.rawValue)")
            }
        } else {
            logger.error("Non-AVError occurred: \(error)")
        }
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("PiP will stop")
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        logger.info("PiP did stop")
        viewModel.handlePipStateChange(isActive: false)
    }
}
