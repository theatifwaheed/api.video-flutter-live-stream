import ApiVideoLiveStream
import AVFoundation
import Foundation

protocol LiveStreamViewManagerDelegate {
    func connectionSuccess()
    func connectionFailed(_: String)
    func disconnection()
    func error(_: Error)
    func videoSizeChanged(_: CGSize)
}

class LiveStreamViewManager: NSObject {
    private let previewTexture: PreviewTexture
    private var liveStream: ApiVideoLiveStream?
    private var isInitialized = false
    private let initializationQueue = DispatchQueue(label: "com.apivideo.livestream.init", qos: .userInitiated)
    private var pendingVideoConfig: VideoConfig?
    private var pendingAudioConfig: AudioConfig?
    
    // Default configs for fallback (computed properties)
    private var defaultVideoConfig: VideoConfig {
        return VideoConfig(
            bitrate: 3_000_000,
            resolution: CGSize(width: 1280, height: 720),
            fps: Float64(30),
            gopDuration: 2.0
        )
    }
    
    private var defaultAudioConfig: AudioConfig {
        return AudioConfig(bitrate: 128_000)
    }

    var delegate: LiveStreamViewManagerDelegate?

    init(textureRegistry: FlutterTextureRegistry) throws {
        previewTexture = PreviewTexture(registry: textureRegistry)
        // Don't initialize ApiVideoLiveStream here - do it lazily in startPreview()
        // This makes create() return quickly without blocking
        super.init()
        
        // Configure audio session early to avoid conflicts during camera initialization
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Log error but don't fail - camera might still work
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func initializeLiveStream() throws {
        guard !isInitialized else {
            return
        }
        
        // AVFoundation operations must be on main thread
        // This is called from startPreview which handles async properly
        liveStream = try ApiVideoLiveStream(
            preview: previewTexture,
            initialAudioConfig: nil,
            initialVideoConfig: nil,
            initialCamera: nil
        )
        liveStream?.delegate = self
        
        // Apply any pending configs
        if let videoConfig = pendingVideoConfig {
            liveStream?.videoConfig = videoConfig
        }
        if let audioConfig = pendingAudioConfig {
            liveStream?.audioConfig = audioConfig
        }
        
        isInitialized = true
    }

    var textureId: Int64 {
        previewTexture.textureId
    }

    private(set) var isStreaming = false

    var videoConfig: VideoConfig {
        get {
            if let liveStream = liveStream {
                return liveStream.videoConfig
            }
            // Return default config if not initialized, or pending config if set
            return pendingVideoConfig ?? defaultVideoConfig
        }
        set {
            if isInitialized, let liveStream = liveStream {
                delegate?.videoSizeChanged(newValue.resolution)
                liveStream.videoConfig = newValue
            } else {
                // Store for later initialization
                pendingVideoConfig = newValue
                delegate?.videoSizeChanged(newValue.resolution)
            }
        }
    }

    var audioConfig: AudioConfig {
        get {
            if let liveStream = liveStream {
                return liveStream.audioConfig
            }
            // Return default config if not initialized, or pending config if set
            return pendingAudioConfig ?? defaultAudioConfig
        }
        set {
            if isInitialized, let liveStream = liveStream {
                liveStream.audioConfig = newValue
            } else {
                // Store for later initialization
                pendingAudioConfig = newValue
            }
        }
    }

    var isMuted: Bool {
        get {
            liveStream?.isMuted ?? false
        }
        set {
            liveStream?.isMuted = newValue
        }
    }

    var cameraPosition: AVCaptureDevice.Position {
        get {
            liveStream?.cameraPosition ?? .back
        }
        set {
            liveStream?.cameraPosition = newValue
        }
    }

    var camera: AVCaptureDevice? {
        get {
            liveStream?.camera
        }
        set {
            liveStream?.camera = newValue
        }
    }

    #if os(iOS)
        /// Zoom on the video capture
        public var zoomRatio: CGFloat {
            get {
                liveStream?.zoomRatio ?? 1.0
            }
            set(newValue) {
                liveStream?.zoomRatio = newValue
            }
        }
    #endif

    func dispose() {
        liveStream?.stopStreaming()
        liveStream?.stopPreview()
        previewTexture.dispose()
        liveStream = nil
        isInitialized = false
    }

    func startPreview(completion: @escaping (Result<Void, Error>) -> Void) {
        // Initialize lazily on first preview start
        // Use background queue for preparation, but AVFoundation requires main thread
        initializationQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "LiveStreamViewManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Manager was deallocated"])))
                }
                return
            }
            
            // Switch to main thread for AVFoundation operations
            DispatchQueue.main.async {
                do {
                    // Initialize on main thread (required by AVFoundation)
                    try self.initializeLiveStream()
                    self.liveStream?.startPreview()
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func stopPreview() {
        liveStream?.stopPreview()
    }

    func startStreaming(streamKey: String, url: String) throws {
        // Ensure initialized before streaming
        if !isInitialized {
            try initializeLiveStream()
        }
        guard let liveStream = liveStream else {
            throw NSError(domain: "LiveStreamViewManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Live stream not initialized"])
        }
        try liveStream.startStreaming(streamKey: streamKey, url: url)
        isStreaming = true
    }

    func stopStreaming() {
        liveStream?.stopStreaming()
        isStreaming = false
    }
}

extension LiveStreamViewManager: ApiVideoLiveStreamDelegate {
    /// Called when the connection to the rtmp server is successful
    func connectionSuccess() {
        delegate?.connectionSuccess()
    }

    /// Called when the connection to the rtmp server failed
    func connectionFailed(_ message: String) {
        isStreaming = false
        delegate?.connectionFailed(message)
    }

    /// Called when the connection to the rtmp server is closed
    func disconnection() {
        isStreaming = false
        delegate?.disconnection()
    }

    /// Called if an error happened during the audio configuration
    func audioError(_ error: Error) {
        delegate?.error(error)
    }

    /// Called if an error happened during the video configuration
    func videoError(_ error: Error) {
        delegate?.error(error)
    }
}

