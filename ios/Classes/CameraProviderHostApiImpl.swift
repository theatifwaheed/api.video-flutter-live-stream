import AVFoundation

enum DeviceProvider {
    private static var cachedDevices: [AVCaptureDevice]?
    private static let cacheQueue = DispatchQueue(label: "com.apivideo.camera.cache", qos: .utility)
    private static let discoveryQueue = DispatchQueue(label: "com.apivideo.camera.discovery", qos: .userInitiated)
    
    static func getAvailableCamera() -> [AVCaptureDevice] {
        // Return cached devices if available
        if let cached = cachedDevices {
            return cached
        }
        
        // Use background queue for discovery to avoid blocking
        var devices: [AVCaptureDevice] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        discoveryQueue.async {
            devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
                mediaType: .video,
                position: .unspecified
            ).devices
            
            // Cache the result
            cacheQueue.sync {
                cachedDevices = devices
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return devices
    }

    static func getCamera(uniqueID: String) -> AVCaptureDevice? {
        return getAvailableCamera().first(where: { $0.uniqueID == uniqueID })
    }
    
    static func invalidateCache() {
        cacheQueue.async {
            cachedDevices = nil
        }
    }
}

class CameraProviderHostApiImpl: CameraProviderHostApi {
    func getAvailableCameraIds() throws -> [String] {
        // Use cached device list for faster access
        return DeviceProvider.getAvailableCamera().map { $0.uniqueID }
    }
}
