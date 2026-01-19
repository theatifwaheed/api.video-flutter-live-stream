---
name: Optimize iOS Camera Initialization for Live Streaming
overview: Fix the 10-20 second camera initialization lag on iOS by making camera setup asynchronous, pre-warming the camera session, and optimizing the initialization sequence to match the performance of other camera packages.
todos:
  - id: "1"
    content: Modify LiveStreamHostApiImpl.swift to make create() method async and use background queue for camera initialization
    status: completed
  - id: "2"
    content: Add AVAudioSession configuration in LiveStreamViewManager before camera initialization (similar to native iOS pattern)
    status: completed
  - id: "3"
    content: Implement lazy camera initialization - only initialize camera when startPreview() is called, not in init()
    status: completed
  - id: "4"
    content: Optimize CameraProviderHostApiImpl to cache camera device list and use background queue for discovery
    status: completed
  - id: "5"
    content: Update Flutter controller to pre-warm camera earlier (when screen appears) instead of waiting for user action
    status: completed
  - id: "6"
    content: Add proper loading states and ensure UI remains responsive during background initialization
    status: completed
  - id: "7"
    content: Test on iOS device to verify initialization time is reduced to 1-3 seconds
    status: pending
---

# Optimize iOS Camera Initialization for Live Streaming

## Problem Analysis

The camera initialization in `api.video-flutter-live-stream` package is blocking the main thread on iOS, causing 10-20 second freezes when `_initCameraController()` is called. The issue occurs in:

1. **Flutter Controller** (`live_stream_controller.dart:844`): `liveStreamController!.initialize()` blocks
2. **Platform Bridge** (`LiveStreamHostApiImpl.swift:15`): `create()` method creates `LiveStreamViewManager` synchronously
3. **LiveStreamViewManager** (`LiveStreamViewManager.swift:21`): `ApiVideoLiveStream` initialization happens synchronously on main thread

## Solution Strategy

Based on the native iOS implementation pattern (using async/await with Task), we need to:

1. **Make camera initialization asynchronous** - Move heavy camera setup off main thread
2. **Pre-warm camera session** - Initialize camera earlier in background
3. **Optimize initialization sequence** - Configure audio session first, then camera
4. **Add proper threading** - Use background queues for camera operations

## Implementation Plan

### 1. Modify LiveStreamHostApiImpl.swift

**File**: `/Users/theatifwaheed/Documents/code/packages/api.video-flutter-live-stream/ios/Classes/LiveStreamHostApiImpl.swift`

- Change `create()` method to be async and use background queue
- Initialize `LiveStreamViewManager` on background thread
- Return texture ID after initialization completes

**Changes**:

```swift
func create(completion: @escaping (Result<Int64, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        do {
            let flutterView = try self?.instanceManager.create(textureRegistry: self!.textureRegistry)
            flutterView?.delegate = self
            DispatchQueue.main.async {
                completion(.success(flutterView!.textureId))
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
}
```

### 2. Optimize LiveStreamViewManager Initialization

**File**: `/Users/theatifwaheed/Documents/code/packages/api.video-flutter-live-stream/ios/Classes/Manager/LiveStreamViewManager.swift`

- Configure AVAudioSession before camera initialization
- Use async initialization pattern
- Add lazy initialization for camera device

**Changes**:

- Add `configureAudioSession()` method (similar to native iOS implementation)
- Make camera initialization lazy - only initialize when `startPreview()` is called
- Configure audio session in init before camera setup

### 3. Pre-warm Camera in Flutter Controller

**File**: `/Users/theatifwaheed/Documents/code/tadawuly-flutter/lib/core/view/live_stream_functionality/controller/live_stream_controller.dart`

- Start camera initialization earlier (when screen appears, not when user taps "Go Live")
- Use `compute()` or `Isolate` for heavy operations
- Show loading indicator immediately while camera initializes in background

**Changes**:

- Move `_initCameraControllerWithPermissions()` call earlier in the flow
- Initialize camera when screen first appears (in `init()` method)
- Add proper loading states to prevent UI blocking

### 4. Optimize Camera Device Discovery

**File**: `/Users/theatifwaheed/Documents/code/packages/api.video-flutter-live-stream/ios/Classes/CameraProviderHostApiImpl.swift`

- Cache camera device list to avoid repeated discovery
- Use background queue for device enumeration

**Changes**:

- Add static cache for available cameras
- Use `DispatchQueue.global()` for device discovery

### 5. Add Background Thread Support

**File**: `/Users/theatifwaheed/Documents/code/packages/api.video-flutter-live-stream/ios/Classes/Manager/InstanceManager.swift`

- Ensure instance creation happens on appropriate thread
- Add thread safety for camera operations

## Key Optimizations

1. **Audio Session First**: Configure AVAudioSession before camera (prevents conflicts)
2. **Lazy Camera Init**: Don't initialize camera until actually needed
3. **Background Threading**: All heavy operations on background queues
4. **Pre-warming**: Start initialization earlier in user flow
5. **Caching**: Cache camera device list to avoid repeated discovery

## Testing Checklist

- [ ] Camera initializes in < 2 seconds on iOS
- [ ] UI remains responsive during initialization
- [ ] Loading indicator shows properly
- [ ] No crashes or permission issues
- [ ] Works on both front and back cameras
- [ ] Audio works correctly after optimization
- [ ] Streaming works after optimization

## Files to Modify

1. `packages/api.video-flutter-live-stream/ios/Classes/LiveStreamHostApiImpl.swift`
2. `packages/api.video-flutter-live-stream/ios/Classes/Manager/LiveStreamViewManager.swift`
3. `packages/api.video-flutter-live-stream/ios/Classes/CameraProviderHostApiImpl.swift`
4. `tadawuly-flutter/lib/core/view/live_stream_functionality/controller/live_stream_controller.dart`
5. `tadawuly-flutter/lib/core/view/live_stream_functionality/screens/live_stream_starter/live_stream_starter.dart`

## Expected Outcome

Camera initialization should complete in 1-3 seconds instead of 10-20 seconds, with UI remaining fully responsive throughout the process.