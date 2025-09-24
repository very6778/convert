import Foundation
import CoreGraphics
import AVFoundation

public struct ConversionSettings {
    // Image conversion settings
    var imageQuality: CGFloat = 0.95
    var preserveMetadata: Bool = true
    var maintainAspectRatio: Bool = true
    var resizeImage: Bool = false
    var targetSize: CGSize = CGSize(width: 1920, height: 1080)
    var resizeVideo: Bool = false
    var smartCompressionEnabled: Bool = false
    var smartCompressionCodec: SmartCompressionCodec = .hevc
    var enhanceImage: Bool = false
    var adjustColors: Bool = false
    var saturation: Double = 1.0
    var brightness: Double = 0.0
    var contrast: Double = 1.0
    
    // Video conversion settings
    var videoQuality: String = AVAssetExportPresetHighestQuality
    var videoBitRate: Int = 10_000_000
    var audioBitRate: Int = 256_000
    var frameRate: Int = 30
    var videoDuration: Double = 10.0
    
    // Animation settings
    var gifFrameCount: Int = 10
    var gifFrameDuration: Double = 0.1
    var animationStyle: AnimationStyle = .none
    
    // Audio mixing settings
    var audioStartVolume: Float = 1.0
    var audioEndVolume: Float = 1.0
    
    // Memory thresholds
    var memoryThresholdPercentage: Double = 0.5 // Use up to 50% of available memory
    
    // Validation thresholds
    var minimumVideoBitRate: Int = 100_000    // 100 Kbps
    var minimumAudioBitRate: Int = 64_000     // 64 Kbps
    
    public enum AnimationStyle {
        case none
        case zoom
        case rotate
    }
    
    public enum SmartCompressionCodec: String, CaseIterable, Identifiable {
        case hevc
        case h264

        public var id: String { rawValue }

        var displayName: String {
            switch self {
            case .hevc: return "HEVC"
            case .h264: return "H.264"
            }
        }
    }

    public init(
        imageQuality: Double = 0.8,
        preserveMetadata: Bool = true,
        maintainAspectRatio: Bool = true,
        resizeImage: Bool = false,
        targetSize: CGSize = CGSize(width: 1920, height: 1080),
        resizeVideo: Bool = false,
        smartCompressionEnabled: Bool = false,
        smartCompressionCodec: SmartCompressionCodec = .hevc,
        enhanceImage: Bool = false,
        adjustColors: Bool = false,
        saturation: Double = 1.0,
        brightness: Double = 0.0,
        contrast: Double = 1.0,
        videoQuality: String = AVAssetExportPresetHighestQuality,
        videoBitRate: Int = 10_000_000,
        audioBitRate: Int = 256_000,
        frameRate: Int = 30,
        videoDuration: Double = 10.0,
        gifFrameCount: Int = 10,
        gifFrameDuration: Double = 0.1,
        animationStyle: AnimationStyle = .none
    ) {
        self.imageQuality = imageQuality
        self.preserveMetadata = preserveMetadata
        self.maintainAspectRatio = maintainAspectRatio
        self.resizeImage = resizeImage
        self.targetSize = targetSize
        self.resizeVideo = resizeVideo
        self.smartCompressionEnabled = smartCompressionEnabled
        self.smartCompressionCodec = smartCompressionCodec
        self.enhanceImage = enhanceImage
        self.adjustColors = adjustColors
        self.saturation = saturation
        self.brightness = brightness
        self.contrast = contrast
        self.videoQuality = videoQuality
        self.videoBitRate = videoBitRate
        self.audioBitRate = audioBitRate
        self.frameRate = frameRate
        self.videoDuration = videoDuration
        self.gifFrameCount = gifFrameCount
        self.gifFrameDuration = gifFrameDuration
        self.animationStyle = animationStyle
    }
}
