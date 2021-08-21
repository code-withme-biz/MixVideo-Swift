//
//  ViewController.swift
//  MixMedia
//
//  Created by Catalina on 2021/6/22.
//

import UIKit
import AVFoundation
import AVKit
import MobileCoreServices
import MediaPlayer
import Photos

class ViewController: UIViewController {
    var firstAsset: AVAsset?
    var secondAsset: AVAsset?
    var loadingAssetOne = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Remove this code in case of loading videos from library
        firstAsset = AVAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "v1", ofType: "mov")!))
        secondAsset = AVAsset(url: URL(fileURLWithPath: Bundle.main.path(forResource: "v2", ofType: "mp4")!))
    }

    func exportDidFinish(_ session: AVAssetExportSession) {
        // Cleanup assets
        firstAsset = nil
        secondAsset = nil
        
        guard
            session.status == AVAssetExportSession.Status.completed,
            let outputURL = session.outputURL
        else { return }

        let saveVideoToPhotos = {
            let changes: () -> Void = {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
            }
            PHPhotoLibrary.shared().performChanges(changes) { saved, error in
                DispatchQueue.main.async {
                    let success = saved && (error == nil)
                    let title = success ? "Success" : "Error"
                    let message = success ? "Video saved" : "Failed to save video"

                    let alert = UIAlertController(
                        title: title,
                        message: message,
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(
                                        title: "OK",
                                        style: UIAlertAction.Style.cancel,
                                        handler: nil))
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }

        // Ensure permission to access Photo Library
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    saveVideoToPhotos()
                }
            }
        } else {
            saveVideoToPhotos()
        }
        
        DispatchQueue.main.async {
            let player = AVPlayer(url: outputURL)
            let vcPlayer = AVPlayerViewController()
            vcPlayer.player = player
            self.present(vcPlayer, animated: true, completion: nil)
        }
    }

    func savedPhotosAvailable() -> Bool {
        guard !UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum)
        else { return true }

        let alert = UIAlertController(
            title: "Not Available",
            message: "No Saved Album found",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: "OK",
            style: UIAlertAction.Style.cancel,
            handler: nil))
        present(alert, animated: true, completion: nil)
        return false
    }
    
    @IBAction func actionLoadFirstVideo(_ sender: Any) {
        if savedPhotosAvailable() {
            loadingAssetOne = true
            VideoHelper.startMediaBrowser(delegate: self, sourceType: .savedPhotosAlbum)
        }
    }
    
    @IBAction func actionLoadSecondVideo(_ sender: Any) {
        if savedPhotosAvailable() {
            loadingAssetOne = false
            VideoHelper.startMediaBrowser(delegate: self, sourceType: .savedPhotosAlbum)
        }
    }
    @IBAction func actionPlay(_ sender: Any) {
        guard
            let firstAsset = firstAsset,
            let secondAsset = secondAsset
        else { return }

        // Create AVMutableComposition object
        let mixComposition = AVMutableComposition()

        // Create video track
        guard
            let videoTrack = mixComposition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
          else { return }

        do {
            try videoTrack.insertTimeRange(
                CMTimeRangeMake(start: .zero, duration: firstAsset.duration),
                of: firstAsset.tracks(withMediaType: .video)[0],
                at: .zero)
        } catch {
            print("Failed to load video track")
            return
        }

        // Composition Instruction
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRangeMake(
            start: .zero,
            duration: firstAsset.duration)

        // Set up the instruction
        let layerInstruction = VideoHelper.videoCompositionInstruction(
            videoTrack,
            asset: firstAsset)
        mainInstruction.layerInstructions = [layerInstruction]
        let mainComposition = AVMutableVideoComposition()
        mainComposition.instructions = [mainInstruction]
        mainComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        mainComposition.renderSize = CGSize(
            width: UIScreen.main.bounds.width,
            height: UIScreen.main.bounds.height)

        // Audio track
        guard
            let secondTrack = mixComposition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
            else { return }

        do {
            try secondTrack.insertTimeRange(
                CMTimeRangeMake(start: .zero, duration: firstAsset.duration),
                of: secondAsset.tracks(withMediaType: .audio)[0],
                at: .zero)
        } catch {
            print("Failed to load second track")
            return
        }

        // Get path
        guard
            let documentDirectory = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask).first
        else { return }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let date = dateFormatter.string(from: Date())
        let url = documentDirectory.appendingPathComponent("mergeVideo-\(date).m4v")

        // Create Exporter
        guard
            let exporter = AVAssetExportSession(
                asset: mixComposition,
                presetName: AVAssetExportPresetHighestQuality)
        else { return }
        exporter.outputURL = url
        exporter.outputFileType = AVFileType.m4v
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = mainComposition

        // Perform play
        exporter.exportAsynchronously(completionHandler: {
            switch exporter.status {
            case .failed:
                if let _error = exporter.error {
                    print(_error.localizedDescription)
                }
                break
            case .cancelled:
                print("canceled")
            default:
                print("finished")
                self.exportDidFinish(exporter)
            }
        })
    }
}

// MARK: - UIImagePickerControllerDelegate
extension ViewController: UIImagePickerControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any])
    {
        dismiss(animated: true, completion: nil)
        guard let mediaType = info[UIImagePickerController.InfoKey.mediaType] as? String,
              mediaType == (kUTTypeMovie as String),
              let url = info[UIImagePickerController.InfoKey.mediaURL] as? URL
        else { return }

        let avAsset = AVAsset(url: url)
        var message = ""
        if loadingAssetOne {
            message = "Video one loaded"
            firstAsset = avAsset
        } else {
            message = "Video two loaded"
            secondAsset = avAsset
        }
        let alert = UIAlertController(title: "Asset Loaded",
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(
                            title: "OK",
                            style: UIAlertAction.Style.cancel,
                            handler: nil))
        present(alert, animated: true, completion: nil)
    }
}

// MARK: - UINavigationControllerDelegate
extension ViewController: UINavigationControllerDelegate {}
