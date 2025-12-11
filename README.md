Syphon is an open source macOS technology that allows applications to share video and still images with one another in realtime.

## Apple Silicon + Metal 4 Optimized 🚀

**Latest Update:** Syphon Framework now supports **Metal 4** with full Apple Silicon optimizations!

### Metal 4 Features
- ✅ **Unified Command Encoders** - Lower overhead, faster performance
- ✅ **Improved Shader Compilation** - Reduced compilation time
- ✅ **Explicit Residency Management** - Better memory control
- ✅ **MetalFX Ready** - Frame interpolation support

### Apple Silicon Optimizations
- ✅ **Native Metal 4 API** with zero-copy texture sharing
- ✅ **Unified Memory Architecture** - Optimal for M1/M2/M3/M4
- ✅ **Tile-Based Deferred Rendering** (TBDR) - Maximum GPU efficiency
- ✅ **Half-precision shaders** - 2x performance on Apple GPUs
- ✅ **Automatic hardware detection** and optimization

### Getting Started

For new projects, use `SyphonMetalServer` and `SyphonMetalClient` for best performance:
- 📖 **Objective-C**: See [APPLE_SILICON_MIGRATION.md](APPLE_SILICON_MIGRATION.md)
- 📖 **Swift**: See [SWIFT_GUIDE_JA.md](SWIFT_GUIDE_JA.md) (日本語ガイド)

**System Requirements:**
- macOS 15.0+ (for full Metal 4 features)
- Apple Silicon (M1 or later) or A14 Bionic or later

## More Information

See http://syphon.github.io for more information.

This project hosts the Syphon.framework for developers who want to integrate Syphon in their own software. If you are looking for the Syphon plugins for Quartz Composer, Max/Jitter, FFGL, etc, the project for the Syphon Implementations currently at http://github.com/Syphon

## Quick Example (Swift)

```swift
import Syphon
import Metal

// Create server
let device = MTLCreateSystemDefaultDevice()!
let server = SyphonMetalServer(name: "My Server", device: device, options: nil)

// Publish frame
let commandBuffer = commandQueue.makeCommandBuffer()!
server.publishFrameTexture(texture,
                          on: commandBuffer,
                          imageRegion: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                          flipped: false)
commandBuffer.commit()
```

See documentation for complete examples and best practices.
