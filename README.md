Syphon is an open source macOS technology that allows applications to share video and still images with one another in realtime.

## Apple Silicon Optimized

**New in this version:** Syphon Framework has been fully optimized for Apple Silicon!

- ✅ **Native Metal API** with zero-copy texture sharing
- ✅ **Unified Memory Architecture** optimizations
- ✅ **Tile-Based Deferred Rendering** for maximum GPU efficiency
- ✅ **Half-precision shaders** optimized for Apple GPUs
- ✅ **Automatic hardware detection** and optimization

For new projects, use `SyphonMetalServer` and `SyphonMetalClient` for best performance on Apple Silicon. See [APPLE_SILICON_MIGRATION.md](APPLE_SILICON_MIGRATION.md) for migration guide.

## More Information

See http://syphon.github.io for more information.

This project hosts the Syphon.framework for developers who want to integrate Syphon in their own software. If you are looking for the Syphon plugins for Quartz Composer, Max/Jitter, FFGL, etc, the project for the Syphon Implementations currently at http://github.com/Syphon
