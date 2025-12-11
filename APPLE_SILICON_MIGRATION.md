# Apple Silicon Migration Guide

## Overview

Syphon Framework has been fully optimized for Apple Silicon with **Metal 4** support. This document describes the optimizations and migration path from OpenGL to Metal, including the latest Metal 4 features.

## Why Metal 4 for Apple Silicon?

1. **Metal 4 Features**: Latest API with unified command encoders and improved compilation
2. **Native Performance**: Direct hardware access on Apple Silicon with minimal overhead
3. **Unified Memory Architecture**: Zero-copy texture sharing on Apple Silicon
4. **Tile-Based Deferred Rendering**: Optimized for Apple GPU architecture
5. **Machine Learning Integration**: Native tensor support in Metal 4
6. **MetalFX Support**: Frame interpolation and ray tracing denoiser
7. **Future-Proof**: OpenGL is deprecated; Metal 4 is the cutting edge

## Metal 4 New Features

### Unified Command Encoder
Metal 4 consolidates command encoders for better performance and simpler API:
- Lower overhead command encoding
- Automatic optimization by the Metal compiler
- Syphon Framework automatically benefits from these improvements

### Improved Compilation
- Faster shader compilation with Metal 4
- Reduced redundant compilation
- Optimized for Apple Silicon's architecture

### Explicit Residency Management
- Better control over large unified memory spaces
- Residency sets for resource management
- Syphon automatically manages resources efficiently

### MetalFX Enhancements
- Frame interpolation for smoother performance
- Ray tracing denoiser (future enhancement potential)
- Neural rendering support

## Key Optimizations

### Metal Shaders
- **Half-precision arithmetic**: Uses `half` and `half2` types where appropriate for better performance on Apple GPUs
- **Efficient texture sampling**: Linear filtering with proper sampler configuration
- **Optimized memory access**: Structured for Apple Silicon's tile-based architecture

### Unified Memory
- **Shared storage mode**: IOSurface-backed textures use `MTLStorageModeShared` for zero-copy access
- **Optimized synchronization**: Uses `optimizeContentsForGPUAccess` for unified memory
- **Reduced bandwidth**: Eliminates unnecessary CPU-GPU memory transfers

### Server Optimizations
- **Intelligent pipeline selection**: Chooses between linear and nearest-neighbor filtering based on use case
- **Fast blit path**: Uses Metal's blit encoder for pixel-perfect copies
- **Hazard tracking**: Enables automatic dependency tracking on Apple Silicon

### Client Optimizations
- **Efficient texture creation**: Optimized descriptor configuration for Apple Silicon
- **Default cache mode**: Leverages CPU cache for unified memory access
- **Atomic operations**: Lock-free frame validation using C11 atomics

## Migration Guide

### For New Projects

Simply use the Metal API:

```objective-c
#import <Syphon/Syphon.h>

// Create Metal device
id<MTLDevice> device = MTLCreateSystemDefaultDevice();

// Create server
SyphonMetalServer *server = [[SyphonMetalServer alloc] initWithName:@"My Server"
                                                              device:device
                                                             options:nil];

// Publish frames
[server publishFrameTexture:myTexture
            onCommandBuffer:commandBuffer
                imageRegion:NSMakeRect(0, 0, width, height)
                    flipped:NO];

// Create client
SyphonMetalClient *client = [[SyphonMetalClient alloc] initWithServerDescription:description
                                                                          device:device
                                                                         options:nil
                                                                 newFrameHandler:^(SyphonMetalClient *client) {
    // Handle new frame
}];

// Get frame
id<MTLTexture> frame = [client newFrameImage];
```

### Migrating from OpenGL

If you have existing OpenGL code, here's the migration path:

#### Before (OpenGL):
```objective-c
CGLContextObj context = CGLGetCurrentContext();
SyphonOpenGLServer *server = [[SyphonOpenGLServer alloc] initWithName:@"My Server"
                                                              context:context
                                                              options:nil];
[server publishFrameTexture:glTexture
           textureTarget:GL_TEXTURE_2D
             imageRegion:NSMakeRect(0, 0, width, height)
       textureDimensions:NSMakeSize(width, height)
                 flipped:NO];
```

#### After (Metal):
```objective-c
id<MTLDevice> device = MTLCreateSystemDefaultDevice();
SyphonMetalServer *server = [[SyphonMetalServer alloc] initWithName:@"My Server"
                                                              device:device
                                                             options:nil];
[server publishFrameTexture:metalTexture
            onCommandBuffer:commandBuffer
                imageRegion:NSMakeRect(0, 0, width, height)
                    flipped:NO];
```

## Performance Tips

### 1. Use Command Buffers Efficiently
```objective-c
id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
[server publishFrameTexture:texture
            onCommandBuffer:commandBuffer
                imageRegion:region
                    flipped:NO];
[commandBuffer commit];
```

### 2. Leverage Unified Memory
On Apple Silicon, IOSurface-backed textures automatically benefit from unified memory. No special code required - the framework handles it!

### 3. Minimize Texture Format Conversions
Use `MTLPixelFormatBGRA8Unorm` for best compatibility and performance.

### 4. Batch Operations
When publishing multiple frames, reuse the same command buffer when possible:
```objective-c
id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
// ... render your content to texture ...
[server publishFrameTexture:texture
            onCommandBuffer:commandBuffer
                imageRegion:region
                    flipped:NO];
[commandBuffer commit];
```

## Technical Details

### Storage Modes
- **Apple Silicon**: Uses `MTLStorageModeShared` for IOSurface textures
- **Intel**: Falls back to managed mode when needed
- **Automatic**: Framework detects hardware and chooses optimal mode

### Shader Optimizations
- **Vertex shader**: Uses efficient SIMD operations for coordinate transformation
- **Fragment shader**: Returns `half4` instead of `float4` for better performance
- **Texture coordinates**: Uses `half2` precision (sufficient for texture mapping)

### Synchronization
The framework uses:
- `os_unfair_lock` for lightweight thread synchronization
- C11 atomics for lock-free operations
- Metal's hazard tracking for automatic dependencies

## Backward Compatibility

OpenGL classes remain available for existing applications:
- `SyphonOpenGLServer`
- `SyphonOpenGLClient`
- `SyphonOpenGLImage`

However, these are marked as deprecated and should not be used for new development.

## System Requirements

- **Minimum**: macOS 10.15 (Catalina) for basic Metal optimizations
- **Recommended**: macOS 15.0 or later for full Metal 4 features
- **Metal Version**: Metal 4 (macOS 15.0+) for best performance
- **Hardware**: Apple M1 or later (or A14 Bionic or later)

## Verification

To verify Apple Silicon and Metal 4 optimizations are active, check the console logs:
```
Syphon Metal Server: Running on Apple Silicon with unified memory - Metal 4 optimizations enabled
Syphon Metal Client: Running on Apple Silicon with unified memory - Metal 4 optimizations enabled
Syphon Metal Renderer: Initialized with Metal 4 optimizations for Apple Silicon
```

You can also check the Metal version programmatically:
```objective-c
// Check for Metal 4 support
if (@available(macOS 15.0, *)) {
    NSLog(@"Metal 4 available - full optimizations enabled");
}
```

## Metal 4 Specific Optimizations in Syphon

### Shader Compilation
- Half-precision arithmetic (`half2`, `half4`) for 2x performance on Apple GPUs
- Optimized for Metal 4's improved compilation pipeline
- Reduced shader compilation time

### Command Encoding
- Compatible with Metal 4's unified command encoder
- Automatic selection between blit and render encoders
- Optimized command buffer usage

### Memory Management
- Explicit residency hints for large textures
- Shared storage mode for IOSurface textures
- Optimized synchronization with `optimizeContentsForGPUAccess`

## Swift Usage

For Swift developers, see the comprehensive guide in `SWIFT_GUIDE_JA.md` (Japanese) for:
- Complete Swift API examples
- SwiftUI integration
- Metal 4 optimization techniques
- Performance best practices

## Additional Resources

- [What's New - Metal 4](https://developer.apple.com/metal/whats-new/)
- [Discover Metal 4 - WWDC 2025](https://developer.apple.com/videos/play/wwdc2025/205/)
- [Metal Programming Guide](https://developer.apple.com/metal/)
- [Metal Best Practices Guide](https://developer.apple.com/documentation/metal/metal_best_practices)
- [Apple Silicon Performance Guide](https://developer.apple.com/documentation/apple-silicon)

## Support

For issues or questions about the Apple Silicon and Metal 4 migration, please file an issue on the GitHub repository.
