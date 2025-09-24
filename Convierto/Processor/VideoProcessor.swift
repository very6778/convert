import AVFoundation
import UniformTypeIdentifiers
import CoreImage
import AppKit
import os
import AudioToolbox
import VideoToolbox

protocol ResourceManaging {
    func cleanup()
}

class VideoProcessor: BaseConverter {
    private weak var processorFactory: ProcessorFactory?
    private let audioVisualizer: AudioVisualizer
    private let imageProcessor: ImageProcessor
    private let coordinator: ConversionCoordinator
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Convierto", category: "VideoProcessor")
    
    required init(settings: ConversionSettings = ConversionSettings()) throws {
        self.audioVisualizer = AudioVisualizer(size: CGSize(width: 1920, height: 1080))
        self.imageProcessor = try ImageProcessor(settings: settings)
        self.coordinator = ConversionCoordinator(settings: settings)
        try super.init(settings: settings)
    }
    
    convenience init(settings: ConversionSettings = ConversionSettings(), factory: ProcessorFactory? = nil) throws {
        try self.init(settings: settings)
        self.processorFactory = factory
    }
    
    override func convert(_ url: URL, to format: UTType, metadata: ConversionMetadata, progress: Progress) async throws -> ProcessingResult {
        let conversionId = UUID()
        logger.debug("🎬 Starting video conversion (ID: \(conversionId.uuidString))")
        
        await coordinator.trackConversion(conversionId)
        
        defer {
            Task {
                logger.debug("🏁 Completing video conversion (ID: \(conversionId.uuidString))")
                await coordinator.untrackConversion(conversionId)
            }
        }
        
        logger.debug("📂 Input URL: \(url.path(percentEncoded: false))")
        logger.debug("🎯 Target format: \(format.identifier)")
        
        let asset = AVURLAsset(url: url)
        logger.debug("✅ Created AVURLAsset from provided URL")
        
        // Direct audio extraction for audio formats
        if format.conforms(to: .audio) || format == .mp3 {
            logger.debug("🎵 Using direct audio extraction")
            do {
                return try await extractAudio(from: asset, to: format, metadata: metadata, progress: progress)
            } catch {
                logger.error("❌ Audio extraction failed: \(error.localizedDescription)")
                // Try fallback with different settings
                return try await handleFallback(
                    asset: asset,
                    originalURL: url,
                    to: format,
                    metadata: metadata,
                    progress: progress
                )
            }
        }
        if settings.smartCompressionEnabled && format == .mpeg4Movie && !settings.resizeVideo {
            do {
                return try await performSmartCompression(
                    asset: asset,
                    originalURL: url,
                    format: format,
                    metadata: metadata,
                    progress: progress
                )
            } catch {
                logger.error("❌ Smart compression failed: \(error.localizedDescription). Falling back to standard export")
            }
        }
        
        // Regular video conversion path
        return try await performConversion(
            asset: asset,
            originalURL: url,
            to: format,
            metadata: metadata,
            progress: progress
        )
    }
    
    override func canConvert(from: UTType, to: UTType) -> Bool {
        // Allow direct audio extraction from audiovisual content
        if to.conforms(to: .audio) || to == .mp3 {
            return from.conforms(to: .audiovisualContent) || from.conforms(to: .audio)
        }
        
        // General video conversions
        if from.conforms(to: .audiovisualContent) || to.conforms(to: .audiovisualContent) {
            return true
        }
        
        return false
    }
    
    private func handleFallback(
        asset: AVAsset,
        originalURL: URL,
        to format: UTType,
        metadata: ConversionMetadata,
        progress: Progress
    ) async throws -> ProcessingResult {
        // If output is an image, try extracting a key frame
        if format.conforms(to: .image) {
            logger.debug("🎞 Fallback: Extracting key frame from video as image")
            return try await extractKeyFrame(from: asset, format: format, metadata: metadata)
        }
        
        // Otherwise, try with reduced quality settings
        let fallbackSettings = ConversionSettings(
            videoQuality: AVAssetExportPresetMediumQuality,
            videoBitRate: 1_000_000,
            audioBitRate: 64_000,
            frameRate: 24
        )
        
        logger.debug("🎞 Fallback: Retrying conversion with reduced quality")
        return try await performConversion(
            asset: asset,
            originalURL: originalURL,
            to: format,
            metadata: metadata,
            progress: progress,
            settings: fallbackSettings
        )
    }

    private func performSmartCompression(
        asset: AVAsset,
        originalURL: URL,
        format: UTType,
        metadata: ConversionMetadata,
        progress: Progress
    ) async throws -> ProcessingResult {
        logger.debug("🎯 Smart compression enabled — using HEVC and adaptive bitrate")

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.conversionFailed(reason: "No video track available")
        }

        let transform = try await videoTrack.load(.preferredTransform)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)
        let durationSeconds = max(duration.seconds, 0.0001)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30

        let renderSize: CGSize
        if settings.resizeVideo {
            renderSize = settings.maintainAspectRatio
                ? calculateAspectFitSize(naturalSize, target: settings.targetSize)
                : settings.targetSize
        } else {
            let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
            renderSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        }

        self.updateProgress(progress, fraction: 0.05)

        let resolutionBucket = classifyResolution(for: renderSize)
        let highFrameRate = frameRate >= 48
        let targetBitrate = calculateSmartBitrate(for: resolutionBucket, highFrameRate: highFrameRate)
        logger.debug("📊 Target bitrate: \(targetBitrate) bps for \(renderSize.width)x\(renderSize.height) @ \(frameRate) fps [\(self.describe(bucket: resolutionBucket))]")

        let outputURL = try CacheManager.shared.createTemporaryURL(for: format.preferredFilenameExtension ?? "mp4")

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        let videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSettings)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw ConversionError.conversionFailed(reason: "Unable to configure video reader")
        }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)

        let codec = settings.smartCompressionCodec
        let videoCodec: AVVideoCodecType
        let profileLevel: Any

        switch codec {
        case .hevc:
            videoCodec = .hevc
            profileLevel = kVTProfileLevel_HEVC_Main_AutoLevel
        case .h264:
            videoCodec = .h264
            profileLevel = AVVideoProfileLevelH264HighAutoLevel
        }

        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoProfileLevelKey: profileLevel
        ]

        let videoInputSettings: [String: Any] = [
            AVVideoCodecKey: videoCodec,
            AVVideoWidthKey: Int(renderSize.width.rounded()),
            AVVideoHeightKey: Int(renderSize.height.rounded()),
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoInputSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else {
            throw ConversionError.conversionFailed(reason: "Unable to configure video writer")
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        var audioOutput: AVAssetReaderTrackOutput?

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioReaderSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2
            ]
            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioReaderSettings)
            readerOutput.alwaysCopiesSampleData = false
            if reader.canAdd(readerOutput) {
                reader.add(readerOutput)
                audioOutput = readerOutput

                let audioWriterSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: settings.audioBitRate
                ]
                let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioWriterSettings)
                writerInput.expectsMediaDataInRealTime = false
                if writer.canAdd(writerInput) {
                    writer.add(writerInput)
                    audioInput = writerInput
                }
            }
        }

        guard writer.startWriting() else {
            throw ConversionError.conversionFailed(reason: writer.error?.localizedDescription ?? "Failed to start writer")
        }

        guard reader.startReading() else {
            writer.cancelWriting()
            throw ConversionError.conversionFailed(reason: reader.error?.localizedDescription ?? "Failed to start reader")
        }

        writer.startSession(atSourceTime: .zero)
        progress.totalUnitCount = 100

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let videoQueue = DispatchQueue(label: "com.convierto.smartcompress.video")
            let audioQueue = DispatchQueue(label: "com.convierto.smartcompress.audio")
            let syncQueue = DispatchQueue(label: "com.convierto.smartcompress.sync")
            let group = DispatchGroup()
            group.enter()

            var didFinishVideo = false
            var didFinishAudio = audioInput == nil
            var writingError: Error?

            func finishVideo() {
                if !didFinishVideo {
                    didFinishVideo = true
                    videoInput.markAsFinished()
                    group.leave()
                }
            }

            func finishAudio() {
                if !didFinishAudio {
                    didFinishAudio = true
                    audioInput?.markAsFinished()
                    group.leave()
                }
            }

            func recordError(_ error: Error) {
                syncQueue.sync {
                    if writingError == nil {
                        writingError = error
                        reader.cancelReading()
                        writer.cancelWriting()
                        finishVideo()
                        finishAudio()
                    }
                }
            }

            videoInput.requestMediaDataWhenReady(on: videoQueue) {
                while videoInput.isReadyForMoreMediaData {
                    if syncQueue.sync(execute: { writingError != nil }) {
                        finishVideo()
                        return
                    }

                    guard let sample = videoOutput.copyNextSampleBuffer() else {
                        switch reader.status {
                        case .reading:
                            return
                        case .completed, .cancelled, .failed:
                            finishVideo()
                            return
                        @unknown default:
                            finishVideo()
                            return
                        }
                    }

                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
                    let fraction = min(max(timestamp.seconds / durationSeconds, 0), 1)
                    let videoProgress = Int64(min(84, max(5, 5 + fraction * 75)))
                    DispatchQueue.main.async {
                        if videoProgress > progress.completedUnitCount {
                            progress.completedUnitCount = videoProgress
                        }
                    }
                    self.updateProgress(progress, fraction: Double(videoProgress) / 100.0)

                    if !videoInput.append(sample) {
                        let error = writer.error ?? ConversionError.conversionFailed(reason: "Failed to append video sample")
                        recordError(error)
                        finishVideo()
                        return
                    }
                }
            }

            if let audioOutput = audioOutput, let audioInput = audioInput {
                group.enter()
                audioInput.requestMediaDataWhenReady(on: audioQueue) {
                    while audioInput.isReadyForMoreMediaData {
                        if syncQueue.sync(execute: { writingError != nil }) {
                            finishAudio()
                            return
                        }

                        guard let sample = audioOutput.copyNextSampleBuffer() else {
                            switch reader.status {
                            case .reading:
                                return
                            case .completed, .cancelled, .failed:
                                finishAudio()
                                return
                            @unknown default:
                                finishAudio()
                                return
                            }
                        }

                        if !audioInput.append(sample) {
                            let error = writer.error ?? ConversionError.conversionFailed(reason: "Failed to append audio sample")
                            recordError(error)
                            finishAudio()
                            return
                        }

                        let audioTimestamp = CMSampleBufferGetPresentationTimeStamp(sample)
                        let audioFraction = min(max(audioTimestamp.seconds / durationSeconds, 0), 1)
                        let audioProgress = Int64(min(95, max(85, 85 + audioFraction * 10)))
                        DispatchQueue.main.async {
                            if audioProgress > progress.completedUnitCount {
                                progress.completedUnitCount = audioProgress
                            }
                        }
                        self.updateProgress(progress, fraction: Double(audioProgress) / 100.0)
                    }
                }
            }

            group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                if let error = syncQueue.sync(execute: { writingError }) {
                    writer.cancelWriting()
                    continuation.resume(throwing: error)
                    return
                }

                finishVideo()
                finishAudio()

                writer.finishWriting {
                    switch writer.status {
                    case .completed:
                        DispatchQueue.main.async {
                            progress.completedUnitCount = 100
                        }
                        self.updateProgress(progress, fraction: 1.0)
                        continuation.resume(returning: ())
                    case .failed:
                        let error = writer.error ?? ConversionError.conversionFailed(reason: "Writer failed")
                        continuation.resume(throwing: error)
                    case .cancelled:
                        continuation.resume(throwing: ConversionError.conversionFailed(reason: "Writer cancelled"))
                    default:
                        // Treat unknown as success; the status may be .completed after this closure exits.
                        continuation.resume(returning: ())
                    }
                }
            }
        }

        let resultMetadata = try await extractMetadata(from: asset)
        let cleanedOriginalName = metadata.originalFileName?
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = (cleanedOriginalName?.isEmpty == false) ? cleanedOriginalName! : originalURL.deletingPathExtension().lastPathComponent
        let suggestedFileName = "\(baseName)_smart.mp4"
        return ProcessingResult(
            outputURL: outputURL,
            originalFileName: metadata.originalFileName ?? originalURL.lastPathComponent,
            suggestedFileName: suggestedFileName,
            fileType: format,
            metadata: resultMetadata
        )
    }

    private enum ResolutionBucket {
        case k8, k4, k2, hd1080, hd720, sd480, sd360
    }

    private func classifyResolution(for size: CGSize) -> ResolutionBucket {
        let dimension = Int(max(size.width, size.height))

        switch dimension {
        case 7000...:
            return .k8
        case 3000...:
            return .k4
        case 2000...:
            return .k2
        case 1500...:
            return .hd1080
        case 1000...:
            return .hd720
        case 600...:
            return .sd480
        default:
            return .sd360
        }
    }

    private func calculateSmartBitrate(for bucket: ResolutionBucket, highFrameRate: Bool) -> Int {
        let mbps: Double

        switch (highFrameRate, bucket) {
        case (true, .k8):
            mbps = 54.0
        case (true, .k4):
            mbps = 15.0
        case (true, .k2):
            mbps = 9.0
        case (true, .hd1080):
            mbps = 6.0
        case (true, .hd720):
            mbps = 3.0
        case (true, .sd480):
            mbps = 1.2
        case (true, .sd360):
            mbps = 0.6
        case (false, .k8):
            mbps = 24.0
        case (false, .k4):
            mbps = 9.6
        case (false, .k2):
            mbps = 6.0
        case (false, .hd1080):
            mbps = 3.6
        case (false, .hd720):
            mbps = 1.8
        case (false, .sd480):
            mbps = 0.72
        case (false, .sd360):
            mbps = 0.36
        }

        return bitrate(fromMbps: mbps)
    }

    private func describe(bucket: ResolutionBucket) -> String {
        switch bucket {
        case .k8:
            return "8K"
        case .k4:
            return "4K"
        case .k2:
            return "2K"
        case .hd1080:
            return "1080p"
        case .hd720:
            return "720p"
        case .sd480:
            return "480p"
        case .sd360:
            return "360p"
        }
    }

    private func bitrate(fromMbps value: Double) -> Int {
        Int((value * 1_000_000).rounded())
    }

    private func updateProgress(_ progress: Progress, fraction: Double) {
        let clamped = max(0, min(1, fraction))
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .processingProgressUpdated,
                object: nil,
                userInfo: ["progress": clamped]
            )
        }
    }

    private func performConversion(
        asset: AVAsset,
        originalURL: URL,
        to format: UTType,
        metadata: ConversionMetadata,
        progress: Progress,
        settings: ConversionSettings = ConversionSettings()
    ) async throws -> ProcessingResult {
        let duration = try await asset.load(.duration)
        
        logger.debug("⚙️ Starting conversion process")
        let extensionForFormat = format.preferredFilenameExtension ?? "mp4"
        let outputURL = try CacheManager.shared.createTemporaryURL(for: extensionForFormat)
        
        logger.debug("📂 Output will be written to: \(outputURL.path)")
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: settings.videoQuality) else {
            logger.error("❌ Failed to create AVAssetExportSession for the given asset and preset")
            throw ConversionError.exportFailed(reason: "Failed to create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = getAVFileType(for: format)
        
        // Apply optional audio mix
        if let audioMix = try? await createAudioMix(for: asset) {
            logger.debug("🎵 Applying audio mix to export session")
            exportSession.audioMix = audioMix
        }
        
        // Apply video composition if needed
        if format.conforms(to: .audiovisualContent) && settings.resizeVideo {
            if let videoComposition = try? await createVideoComposition(for: asset) {
                logger.debug("🎥 Applying video composition to export session")
                exportSession.videoComposition = videoComposition
            } else {
                logger.debug("🎥 No video composition applied")
            }
        }
        
        logger.debug("▶️ Starting export session")
        
        let progressTask = Task {
            while !Task.isCancelled {
                let currentProgress = exportSession.progress
                progress.completedUnitCount = Int64(currentProgress * 100)
                logger.debug("📊 Export progress: \(Int(currentProgress * 100))%")
                try? await Task.sleep(nanoseconds: 100_000_000)
                if exportSession.status != .exporting { break }
            }
        }
        
        await exportSession.export()
        progressTask.cancel()
        
        switch exportSession.status {
        case .completed:
            logger.debug("✅ Export completed successfully")
            let resultMetadata = try await extractMetadata(from: asset)
            return ProcessingResult(
                outputURL: outputURL,
                originalFileName: metadata.originalFileName ?? originalURL.lastPathComponent,
                suggestedFileName: "converted_video." + extensionForFormat,
                fileType: format,
                metadata: resultMetadata
            )
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            logger.error("❌ Export failed: \(errorMessage)")
            throw ConversionError.conversionFailed(reason: "Export failed: \(errorMessage)")
        case .cancelled:
            logger.error("❌ Export cancelled")
            throw ConversionError.conversionFailed(reason: "Export cancelled")
        default:
            logger.error("❌ Export ended with unexpected status: \(exportSession.status.rawValue)")
            throw ConversionError.conversionFailed(reason: "Unexpected export status: \(exportSession.status.rawValue)")
        }
    }
    
    func extractKeyFrame(from asset: AVAsset, format: UTType, metadata: ConversionMetadata) async throws -> ProcessingResult {
        logger.debug("🖼 Extracting key frame from video")
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        // Extract first frame
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        let imageRef = try await generator.image(at: time).image
        
        let imageExtension = format.preferredFilenameExtension ?? "jpg"
        let outputURL = try CacheManager.shared.createTemporaryURL(for: imageExtension)
        
        let nsImage = NSImage(cgImage: imageRef, size: NSSize(width: imageRef.width, height: imageRef.height))
        try await imageProcessor.saveImage(nsImage, format: format, to: outputURL, metadata: metadata)
        
        logger.debug("✅ Key frame extracted and saved")
        
        return ProcessingResult(
            outputURL: outputURL,
            originalFileName: metadata.originalFileName ?? "frame",
            suggestedFileName: "extracted_frame." + imageExtension,
            fileType: format,
            metadata: nil
        )
    }
    
    private func createVideoComposition(for asset: AVAsset) async throws -> AVMutableVideoComposition {
        logger.debug("🎥 Creating video composition")
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            logger.error("❌ No video track found for composition")
            throw ConversionError.conversionFailed(reason: "No video track found")
        }
        
        let trackSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)

        let renderSize: CGSize
        if settings.resizeVideo {
            renderSize = settings.maintainAspectRatio
                ? calculateAspectFitSize(trackSize, target: settings.targetSize)
                : settings.targetSize
        } else {
            // Preserve the original display size by using the transformed bounds.
            let transformedRect = CGRect(origin: .zero, size: trackSize).applying(transform)
            renderSize = CGSize(
                width: abs(transformedRect.width),
                height: abs(transformedRect.height)
            )
        }
        
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        var finalTransform = transform
        if settings.resizeVideo {
            let scaleX: CGFloat
            let scaleY: CGFloat

            if settings.maintainAspectRatio {
                let scale = min(
                    renderSize.width / trackSize.width,
                    renderSize.height / trackSize.height
                )
                scaleX = scale
                scaleY = scale
            } else {
                scaleX = renderSize.width / trackSize.width
                scaleY = renderSize.height / trackSize.height
            }

            finalTransform = finalTransform.concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))

            let transformedRect = CGRect(origin: .zero, size: trackSize).applying(finalTransform)
            let translateX = (renderSize.width - transformedRect.width) / 2 - transformedRect.origin.x
            let translateY = (renderSize.height - transformedRect.height) / 2 - transformedRect.origin.y
            finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: translateX, y: translateY))
        }

        layerInstruction.setTransform(finalTransform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        
        return composition
    }
    
    private func calculateAspectFitSize(_ originalSize: CGSize, target: CGSize) -> CGSize {
        let widthRatio = target.width / originalSize.width
        let heightRatio = target.height / originalSize.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
    }
    
    private func extractMetadata(from asset: AVAsset) async throws -> [String: Any] {
        var metadata: [String: Any] = [:]
        
        metadata["duration"] = try await asset.load(.duration).seconds
        metadata["preferredRate"] = try await asset.load(.preferredRate)
        metadata["preferredVolume"] = try await asset.load(.preferredVolume)
        
        if let format = try await asset.load(.availableMetadataFormats).first {
            let items = try await asset.loadMetadata(for: format)
            for item in items {
                if let key = item.commonKey?.rawValue,
                   let value = try? await item.load(.value) {
                    metadata[key] = value
                }
            }
        }
        
        return metadata
    }
    
    func extractAudio(
        from asset: AVAsset,
        to format: UTType,
        metadata: ConversionMetadata,
        progress: Progress
    ) async throws -> ProcessingResult {
        logger.debug("🎵 Starting direct audio extraction")
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            logger.error("❌ No audio track found in the video")
            throw ConversionError.conversionFailed(reason: "No audio track found in video")
        }
        
        // Create export session with audio-specific preset
        let preset = AVAssetExportPresetAppleM4A
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            logger.error("❌ Failed to create export session for audio extraction")
            throw ConversionError.conversionFailed(reason: "Failed to create export session for audio")
        }
        
        // Set up export parameters
        let extensionForAudio = format == .mp3 ? "m4a" : format.preferredFilenameExtension ?? "m4a"
        let outputURL = try CacheManager.shared.createTemporaryURL(for: extensionForAudio)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        
        // Track progress
        let progressTask = Task {
            while !Task.isCancelled {
                let currentProgress = exportSession.progress
                progress.completedUnitCount = Int64(currentProgress * 100)
                logger.debug("📊 Audio export progress: \(Int(currentProgress * 100))%")
                try? await Task.sleep(nanoseconds: 100_000_000)
                if exportSession.status != .exporting { break }
            }
        }
        
        logger.debug("▶️ Starting audio extraction")
        await exportSession.export()
        progressTask.cancel()
        
        switch exportSession.status {
        case .completed:
            logger.debug("✅ Audio extraction completed")
            
            // If MP3 is requested, convert M4A to MP3
            if format == .mp3 {
                return try await convertM4AToMP3(outputURL, metadata: metadata)
            }
            
            let resultMetadata = try await extractMetadata(from: asset)
            return ProcessingResult(
                outputURL: outputURL,
                originalFileName: metadata.originalFileName ?? "audio",
                suggestedFileName: "extracted_audio." + extensionForAudio,
                fileType: format,
                metadata: resultMetadata
            )
            
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            logger.error("❌ Audio extraction failed: \(errorMessage)")
            throw ConversionError.exportFailed(reason: "Failed to extract audio: \(errorMessage)")
            
        case .cancelled:
            logger.error("❌ Audio extraction cancelled")
            throw ConversionError.exportFailed(reason: "Audio extraction was cancelled")
            
        default:
            let statusRaw = exportSession.status.rawValue
            logger.error("❌ Audio extraction ended with unexpected status: \(statusRaw)")
            throw ConversionError.exportFailed(reason: "Unexpected export status: \(statusRaw)")
        }
    }
    
    private func convertM4AToMP3(_ inputURL: URL, metadata: ConversionMetadata) async throws -> ProcessingResult {
        logger.debug("🎵 Converting M4A to MP3")
        
        // First create a temporary M4A file
        let tempM4AURL = try await CacheManager.shared.createTemporaryURL(for: "m4a")
        let asset = AVURLAsset(url: inputURL)
        
        // Create export session with audio preset
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ConversionError.exportFailed(reason: "Failed to create export session for MP3 conversion")
        }
        
        exportSession.outputURL = tempM4AURL
        exportSession.outputFileType = .m4a
        exportSession.audioTimePitchAlgorithm = .spectral
        
        logger.debug("▶️ Starting M4A export")
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            logger.debug("✅ M4A export completed successfully")
            
            // Create final MP3 URL
            let mp3URL = try await CacheManager.shared.createTemporaryURL(for: "mp3")
            
            // Ensure we have write permissions for the output directory
            let outputDirectory = mp3URL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Remove any existing file at the destination
            if FileManager.default.fileExists(atPath: mp3URL.path) {
                try FileManager.default.removeItem(at: mp3URL)
            }
            
            // Move the M4A file to MP3
            try FileManager.default.moveItem(at: tempM4AURL, to: mp3URL)
            
            logger.debug("✅ File successfully moved to: \(mp3URL.path)")
            
            return ProcessingResult(
                outputURL: mp3URL,
                originalFileName: metadata.originalFileName ?? "audio",
                suggestedFileName: "converted_audio.mp3",
                fileType: .mp3,
                metadata: metadata.toDictionary()
            )
            
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            logger.error("❌ MP3 conversion failed: \(errorMessage)")
            throw ConversionError.exportFailed(reason: "Failed to convert to MP3: \(errorMessage)")
            
        case .cancelled:
            logger.error("❌ MP3 conversion cancelled")
            throw ConversionError.exportFailed(reason: "MP3 conversion was cancelled")
            
        default:
            let statusRaw = exportSession.status.rawValue
            logger.error("❌ MP3 conversion ended with unexpected status: \(statusRaw)")
            throw ConversionError.exportFailed(reason: "Unexpected export status: \(statusRaw)")
        }
    }
}
