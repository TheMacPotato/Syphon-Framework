# Syphon デバッグログ追加パッチ

## 概要

Syphonフレームワークに詳細なデバッグログを追加し、レンダリング問題を診断できるようにします。

---

## SyphonMetalServer.m への追加

### publishFrameTexture メソッドにログを追加

```objective-c
- (void)publishFrameTexture:(id<MTLTexture>)textureToPublish onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer imageRegion:(NSRect)region flipped:(BOOL)isFlipped
{
    if(textureToPublish == nil) {
        SYPHONLOG(@"TextureToPublish is nil. Syphon will not publish");
        return;
    }

    // 🆕 デバッグ：入力テクスチャの詳細を出力
    SYPHONLOG(@"📡 publishFrameTexture called:");
    SYPHONLOG(@"   Input texture: %ldx%ld, format: %lu",
              textureToPublish.width, textureToPublish.height,
              (unsigned long)textureToPublish.pixelFormat);
    SYPHONLOG(@"   Input region: (%.0f, %.0f, %.0f, %.0f)",
              region.origin.x, region.origin.y, region.size.width, region.size.height);

    region = NSIntersectionRect(region, NSMakeRect(0, 0, textureToPublish.width, textureToPublish.height));

    // 🆕 デバッグ：クリッピング後のregionを出力
    SYPHONLOG(@"   Clipped region: (%.0f, %.0f, %.0f, %.0f)",
              region.origin.x, region.origin.y, region.size.width, region.size.height);

    id<MTLTexture> destination = [self prepareToDrawFrameOfSize:region.size];

    // 🆕 デバッグ：destination テクスチャの詳細
    SYPHONLOG(@"   Destination texture: %ldx%ld, format: %lu",
              destination.width, destination.height,
              (unsigned long)destination.pixelFormat);

    // When possible, use faster blit encoder (optimized path)
    if( !isFlipped && textureToPublish.pixelFormat == destination.pixelFormat
       && textureToPublish.sampleCount == destination.sampleCount
       && !textureToPublish.framebufferOnly)
    {
        SYPHONLOG(@"   ✅ Using Blit encoder (fast path)");

        id<MTLBlitCommandEncoder> blitCommandEncoder = [commandBuffer blitCommandEncoder];
        blitCommandEncoder.label = @"Syphon Server Blit Encoder (Zero-Copy Path)";

        [blitCommandEncoder copyFromTexture:textureToPublish
                                sourceSlice:0
                                sourceLevel:0
                               sourceOrigin:MTLOriginMake(region.origin.x, region.origin.y, 0)
                                 sourceSize:MTLSizeMake(region.size.width, region.size.height, 1)
                                  toTexture:destination
                           destinationSlice:0
                           destinationLevel:0
                          destinationOrigin:MTLOriginMake(0, 0, 0)];

        // On Apple Silicon with unified memory, optimize synchronization
        if (_supportsUnifiedMemory && @available(macOS 10.15, *)) {
            [blitCommandEncoder optimizeContentsForGPUAccess:destination];
        }

        [blitCommandEncoder endEncoding];
    }
    // Otherwise, use render encoder (when flipping or format conversion needed)
    else
    {
        SYPHONLOG(@"   ⚙️ Using Render encoder (shader path)");
        SYPHONLOG(@"      Reason: flipped=%d, formatMatch=%d, sampleMatch=%d, framebufferOnly=%d",
                  isFlipped,
                  textureToPublish.pixelFormat == destination.pixelFormat,
                  textureToPublish.sampleCount == destination.sampleCount,
                  textureToPublish.framebufferOnly);

        [_renderer renderFromTexture:textureToPublish inTexture:destination region:region onCommandBuffer:commandBuffer flip:isFlipped];

        // Optimize for GPU access on Apple Silicon
        if (_supportsUnifiedMemory && @available(macOS 10.15, *)) {
            id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
            [blitEncoder optimizeContentsForGPUAccess:destination];
            [blitEncoder endEncoding];
        }
    }

    // Publish when command buffer completes
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull commandBuffer) {
        // 🆕 デバッグ：コマンドバッファの完了ステータス
        if (commandBuffer.status == MTLCommandBufferStatusCompleted) {
            SYPHONLOG(@"   ✅ Command buffer completed successfully");
        } else {
            SYPHONLOG(@"   ❌ Command buffer failed: status=%ld, error=%@",
                      (long)commandBuffer.status, commandBuffer.error);
        }
        [self publish];
    }];
}
```

---

## SyphonServerRendererMetal.m への追加

### renderFromTexture メソッドにログを追加

```objective-c
- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture inTexture:(id<MTLTexture>)texture region:(NSRect)region onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer flip:(BOOL)flip
{
    if( texture == nil )
    {
        SYPHONLOG(@"❌ renderFromTexture: destination texture is nil");
        return;
    }

    // 🆕 デバッグ：レンダリングパラメータを出力
    SYPHONLOG(@"🎨 renderFromTexture:");
    SYPHONLOG(@"   Source: %ldx%ld, format: %lu",
              offScreenTexture.width, offScreenTexture.height,
              (unsigned long)offScreenTexture.pixelFormat);
    SYPHONLOG(@"   Destination: %ldx%ld, format: %lu",
              texture.width, texture.height,
              (unsigned long)texture.pixelFormat);
    SYPHONLOG(@"   Region: (%.0f, %.0f, %.0f, %.0f), flip: %d",
              region.origin.x, region.origin.y, region.size.width, region.size.height, flip);

    const MTLViewport viewport = (MTLViewport){region.origin.x, region.origin.y, region.size.width, region.size.height, -1.0, 1.0 };
    vector_uint2 viewportSize = simd_make_uint2(viewport.width, viewport.height);

    // 🆕 デバッグ：ビューポートサイズ
    SYPHONLOG(@"   Viewport size: %u x %u", viewportSize.x, viewportSize.y);

    const float w = viewport.width/2;
    const float h = viewport.height/2;
    const float flipValue = flip ? 1 : -1;

    // Vertex data in a format optimized for Apple Silicon unified memory
    const SYPHONTextureVertex quadVertices[] =
    {
        // Pixel positions (NDC), Texture coordinates
        { {  w,   flipValue * h },  { 1.f, 1.f } },
        { { -w,   flipValue * h },  { 0.f, 1.f } },
        { { -w,  flipValue * -h },  { 0.f, 0.f } },

        { {  w,  flipValue * h },  { 1.f, 1.f } },
        { { -w,  flipValue * -h },  { 0.f, 0.f } },
        { {  w,  flipValue * -h },  { 1.f, 0.f } },
    };

    const NSUInteger numberOfVertices = sizeof(quadVertices) / sizeof(SYPHONTextureVertex);

    // Configure render pass for Apple Silicon tile-based rendering
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    renderPassDescriptor.colorAttachments[0].texture = texture;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

    // On Apple Silicon, hint that we want to use tile memory efficiently
    if (_isAppleSilicon && @available(macOS 11.0, *)) {
        // Tile memory optimization - keep color attachment in tile memory
    }
    // Create a render command encoder
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"Syphon Server Render Encoder (Apple Silicon Optimized)";

    // Set viewport
    [renderEncoder setViewport:viewport];

    // Choose pipeline based on whether we need filtering
    // Use nearest-neighbor for pixel-perfect 1:1 copies, linear for scaling
    BOOL useNearestFilter = (region.size.width == offScreenTexture.width &&
                            region.size.height == offScreenTexture.height &&
                            !flip);
    id<MTLRenderPipelineState> pipeline = useNearestFilter ? _pipelineStateNearest : _pipelineState;
    [renderEncoder setRenderPipelineState:pipeline];

    // 🆕 デバッグ：使用するパイプライン
    SYPHONLOG(@"   Pipeline: %@", useNearestFilter ? @"Nearest (pixel-perfect)" : @"Linear (filtering)");

    // Set vertex data (efficient on Apple Silicon unified memory)
    [renderEncoder setVertexBytes:quadVertices
                           length:sizeof(quadVertices)
                          atIndex:SYPHONVertexInputIndexVertices];
    [renderEncoder setVertexBytes:&viewportSize
                           length:sizeof(viewportSize)
                          atIndex:SYPHONVertexInputIndexViewportSize];

    // Set fragment texture
    [renderEncoder setFragmentTexture:offScreenTexture atIndex:SYPHONTextureIndexZero];

    // Draw the quad
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:numberOfVertices];

    [renderEncoder endEncoding];

    // 🆕 デバッグ：レンダリング完了
    SYPHONLOG(@"   ✅ Render encoding completed");
}
```

---

## SyphonPrivate.h での SYPHONLOG マクロの確認

SyphonPrivate.hに以下のマクロが定義されているはずです：

```objective-c
#ifdef DEBUG
    #define SYPHONLOG(format, ...) NSLog((@"Syphon: " format), ##__VA_ARGS__)
#else
    #define SYPHONLOG(format, ...)
#endif
```

デバッグビルドでログが出力されるようにするため、プロジェクト設定で：
- Build Settings → Preprocessor Macros → Debug に `DEBUG=1` を追加

---

## 使用方法

### 1. パッチの適用

上記の変更を `SyphonMetalServer.m` と `SyphonServerRendererMetal.m` に適用します。

### 2. デバッグビルド

```bash
cd /path/to/Syphon-Framework
xcodebuild -configuration Debug
```

### 3. ログの確認

コンソールアプリまたはXcodeのデバッグコンソールで以下のようなログが出力されます：

```
Syphon: 📡 publishFrameTexture called:
Syphon:    Input texture: 1280x720, format: 80
Syphon:    Input region: (0, 0, 1280, 720)
Syphon:    Clipped region: (0, 0, 1280, 720)
Syphon:    Destination texture: 1280x720, format: 80
Syphon:    ✅ Using Blit encoder (fast path)
Syphon:    ✅ Command buffer completed successfully
```

もし問題がある場合：

```
Syphon: 📡 publishFrameTexture called:
Syphon:    Input texture: 1280x720, format: 80
Syphon:    Input region: (0, 0, 1, 1)  // ← 問題！regionが1x1
Syphon:    Clipped region: (0, 0, 1, 1)
Syphon:    Destination texture: 1x1, format: 80  // ← 1ピクセルのテクスチャ
Syphon:    ⚙️ Using Render encoder (shader path)
Syphon:       Reason: flipped=0, formatMatch=1, sampleMatch=1, framebufferOnly=0
Syphon: 🎨 renderFromTexture:
Syphon:    Source: 1280x720, format: 80
Syphon:    Destination: 1x1, format: 80  // ← 問題！
Syphon:    Region: (0, 0, 1, 1), flip: 0
Syphon:    Viewport size: 1 x 1  // ← 1ピクセルだけレンダリング
Syphon:    Pipeline: Linear (filtering)
Syphon:    ✅ Render encoding completed
```

---

## トラブルシューティング

### ログが出力されない場合

1. `DEBUG=1` がプリプロセッサマクロに設定されているか確認
2. `SyphonPrivate.h` に `SYPHONLOG` マクロが定義されているか確認
3. コンソールアプリで「Syphon」でフィルタリング

### ログから問題を特定する

#### パターン1: Destination texture が小さい

```
Destination texture: 1x1, format: 80
```

**原因**: `imageRegion` が正しく指定されていない、または `ciImage.extent` が小さい

**解決**: `SYPHON_RENDERING_FIX.md` の修正を適用

#### パターン2: Command buffer failed

```
❌ Command buffer failed: status=4, error=...
```

**原因**: GPUエラー（テクスチャフォーマット不一致など）

**解決**: テクスチャフォーマットとピクセルフォーマットを確認

#### パターン3: Region が正しいが表示されない

```
Input region: (0, 0, 1280, 720)
Destination texture: 1280x720, format: 80
✅ Using Blit encoder (fast path)
✅ Command buffer completed successfully
```

**原因**: 入力テクスチャ（textureToPublish）の内容が空

**解決**: CoreImageのレンダリングを確認（`SYPHON_RENDERING_FIX.md` 参照）

---

## まとめ

このデバッグログにより、以下のことが分かります：

1. Syphonに渡されるテクスチャのサイズとフォーマット
2. どのレンダリングパス（Blit / Shader）が使用されているか
3. レンダリング領域（region）が正しいか
4. GPUコマンドが正常に完了しているか

問題の原因を特定したら、`SYPHON_RENDERING_FIX.md` の修正を適用してください。
