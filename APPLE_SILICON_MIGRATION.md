# Apple Silicon Migration Guide

## Overview

Syphon Framework has been optimized for Apple Silicon with native Metal support. This document describes the optimizations and migration path from OpenGL to Metal.

## Why Metal for Apple Silicon?

1. **Native Performance**: Metal is the native graphics API for Apple platforms, providing direct hardware access on Apple Silicon
2. **Unified Memory Architecture**: Optimized for Apple Silicon's unified memory, eliminating unnecessary memory copies
3. **Tile-Based Deferred Rendering**: Leverages Apple GPU architecture for maximum efficiency
4. **Future-Proof**: OpenGL is deprecated by Apple; Metal is the path forward

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

- **Minimum**: macOS 10.15 (Catalina) for full Metal optimizations
- **Recommended**: macOS 11.0 (Big Sur) or later for best Apple Silicon support
- **Metal Version**: Metal 2.3 or later

## Verification

To verify Apple Silicon optimizations are active, check the console logs:
```
Syphon Metal Server: Running on Apple Silicon with unified memory - optimizations enabled
Syphon Metal Client: Running on Apple Silicon with unified memory - optimizations enabled
```

## Additional Resources

- [Metal Programming Guide](https://developer.apple.com/metal/)
- [Metal Best Practices Guide](https://developer.apple.com/documentation/metal/metal_best_practices)
- [Apple Silicon Performance Guide](https://developer.apple.com/documentation/apple-silicon)

## Support

For issues or questions about the Apple Silicon migration, please file an issue on the GitHub repository.
