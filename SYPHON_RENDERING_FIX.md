# Syphon レンダリング問題の修正方法

## 問題の診断

**症状**: OBSでSyphon経由の映像が単色（ピンク）で表示される

**原因**: `CIImage.extent`が正しいサイズになっておらず、1ピクセルだけがレンダリングされ、それが引き伸ばされている

---

## 修正コード（Swift）

### 修正前のコード（問題あり）

```swift
// ❌ 問題のあるコード
let ciImage = CIImage(cvPixelBuffer: yuvPixelBuffer)
ciContext.render(
    ciImage,
    to: outputTexture,
    commandBuffer: commandBuffer,
    bounds: ciImage.extent,  // ← これが(0, 0, 1, 1)などの小さい値になっている
    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
)
```

### 修正後のコード（推奨）

```swift
// ✅ 修正版：boundsを明示的に指定

// 1. CVPixelBufferのサイズを取得
let width = CVPixelBufferGetWidth(yuvPixelBuffer)
let height = CVPixelBufferGetHeight(yuvPixelBuffer)

// 2. CIImageを作成
let ciImage = CIImage(cvPixelBuffer: yuvPixelBuffer)

// 3. デバッグ：extent（範囲）を確認
print("🔍 CIImage.extent: \(ciImage.extent)")
print("   期待値: (0, 0, \(width), \(height))")

// 4. boundsを明示的に指定（CVPixelBufferのサイズに基づく）
let renderBounds = CGRect(x: 0, y: 0, width: width, height: height)

// 5. レンダリング
ciContext.render(
    ciImage,
    to: outputTexture,
    commandBuffer: commandBuffer,
    bounds: renderBounds,  // ← 明示的にサイズを指定
    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
)

// 6. GPU同期
commandBuffer.commit()
commandBuffer.waitUntilCompleted()

// 7. レンダリング後の確認（デバッグ用）
verifyTextureContent(outputTexture)
```

---

## デバッグ用関数

### テクスチャ内容の確認関数

```swift
func verifyTextureContent(_ texture: MTLTexture) {
    let width = texture.width
    let height = texture.height
    let bytesPerRow = width * 4  // BGRA = 4 bytes per pixel

    var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
    let region = MTLRegionMake2D(0, 0, width, height)

    texture.getBytes(&pixelData,
                     bytesPerRow: bytesPerRow,
                     from: region,
                     mipmapLevel: 0)

    // サンプリング位置：左上、中央、右下
    let positions = [
        ("左上", 0, 0),
        ("中央", width / 2, height / 2),
        ("右下", width - 1, height - 1)
    ]

    print("🔍 レンダリング後のテクスチャサンプル:")
    for (label, x, y) in positions {
        let offset = (y * width + x) * 4
        let b = pixelData[offset]
        let g = pixelData[offset + 1]
        let r = pixelData[offset + 2]
        let a = pixelData[offset + 3]
        print("   \(label) (\(x), \(y)): B=\(b), G=\(g), R=\(r), A=\(a)")
    }

    // 統計：非ゼロピクセルの数
    var nonZeroPixels = 0
    for i in stride(from: 0, to: pixelData.count, by: 4) {
        if pixelData[i] != 0 || pixelData[i+1] != 0 ||
           pixelData[i+2] != 0 || pixelData[i+3] != 0 {
            nonZeroPixels += 1
        }
    }
    let totalPixels = width * height
    let percentage = Double(nonZeroPixels) / Double(totalPixels) * 100
    print("   非ゼロピクセル: \(nonZeroPixels) / \(totalPixels) (\(String(format: "%.1f", percentage))%)")

    if nonZeroPixels < totalPixels / 100 {
        print("   ⚠️ 警告：レンダリングされたピクセルが非常に少ない！")
    }
}
```

---

## 代替案：Metal Compute Shaderによる変換

CIContextの問題を完全に回避する方法として、Metal Compute Shaderで直接YUV→BGRA変換を行う方法があります。

### YUVConversion.metal

```metal
#include <metal_stdlib>
using namespace metal;

kernel void nv12ToBGRA(
    texture2d<float, access::read> yTexture [[texture(0)]],
    texture2d<float, access::read> uvTexture [[texture(1)]],
    texture2d<float, access::write> bgraTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    // テクスチャサイズチェック
    if (gid.x >= bgraTexture.get_width() || gid.y >= bgraTexture.get_height()) {
        return;
    }

    // Y（輝度）を読み取り（フル解像度）
    float y = yTexture.read(gid).r;

    // UV（色差）を読み取り（ハーフ解像度）
    float2 uv = uvTexture.read(gid / 2).rg;

    // YUV → RGB変換（BT.709 Full Range）
    float3 yuv = float3(y, uv.x - 0.5, uv.y - 0.5);
    float3 rgb;
    rgb.r = yuv.x + 1.5748 * yuv.z;
    rgb.g = yuv.x - 0.1873 * yuv.y - 0.4681 * yuv.z;
    rgb.b = yuv.x + 1.8556 * yuv.y;

    // クランプ（0.0〜1.0）
    rgb = clamp(rgb, 0.0, 1.0);

    // BGRA順で出力（Syphonの期待する形式）
    bgraTexture.write(float4(rgb.b, rgb.g, rgb.r, 1.0), gid);
}
```

### Swiftでの使用例

```swift
// 1. シェーダーのロード（初期化時に1回だけ）
let library = device.makeDefaultLibrary()!
let kernelFunction = library.makeFunction(name: "nv12ToBGRA")!
let pipelineState = try! device.makeComputePipelineState(function: kernelFunction)

// 2. NV12 CVPixelBufferからYテクスチャとUVテクスチャを作成
var yTextureCache: CVMetalTextureCache?
CVMetalTextureCacheCreate(nil, nil, device, nil, &yTextureCache)

var yTextureRef: CVMetalTexture?
CVMetalTextureCacheCreateTextureFromImage(
    nil, yTextureCache!, yuvPixelBuffer, nil,
    .r8Unorm, width, height, 0, &yTextureRef
)
let yTexture = CVMetalTextureGetTexture(yTextureRef!)!

var uvTextureRef: CVMetalTexture?
CVMetalTextureCacheCreateTextureFromImage(
    nil, yTextureCache!, yuvPixelBuffer, nil,
    .rg8Unorm, width / 2, height / 2, 1, &uvTextureRef
)
let uvTexture = CVMetalTextureGetTexture(uvTextureRef!)!

// 3. Compute Shaderを実行
let commandBuffer = commandQueue.makeCommandBuffer()!
let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
computeEncoder.setComputePipelineState(pipelineState)
computeEncoder.setTexture(yTexture, index: 0)
computeEncoder.setTexture(uvTexture, index: 1)
computeEncoder.setTexture(outputTexture, index: 2)  // IOSurface-backed BGRA texture

let threadGroupSize = MTLSizeMake(16, 16, 1)
let threadGroups = MTLSizeMake(
    (width + 15) / 16,
    (height + 15) / 16,
    1
)
computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
computeEncoder.endEncoding()

commandBuffer.commit()
commandBuffer.waitUntilCompleted()

// 4. Syphonに配信
let syphonCommandBuffer = commandQueue.makeCommandBuffer()!
syphonServer.publishFrameTexture(
    outputTexture,
    on: syphonCommandBuffer,
    imageRegion: NSRect(x: 0, y: 0, width: width, height: height),
    flipped: false
)
syphonCommandBuffer.commit()
```

---

## トラブルシューティング

### ケース1: `ciImage.extent`が正しくない

**症状**: `extent`が(0, 0, 1, 1)など小さい値

**解決策**:
```swift
// CVPixelBufferから明示的にサイズを取得
let width = CVPixelBufferGetWidth(yuvPixelBuffer)
let height = CVPixelBufferGetHeight(yuvPixelBuffer)
let renderBounds = CGRect(x: 0, y: 0, width: width, height: height)
```

### ケース2: CoreImageがBGRAではなくRGBA順で出力している

**症状**: 色が反転（赤⇔青が入れ替わる）

**解決策**:
```swift
// Metal Compute Shaderを使用（出力フォーマットを完全制御）
// または、CIFilterでチャンネルスワップ
```

### ケース3: IOSurfaceへの書き込みが失敗

**症状**: テクスチャがすべて0

**解決策**:
```swift
// storageMode を .shared に設定
textureDescriptor.storageMode = .shared

// または、明示的にIOSurfaceをロック（通常は不要）
IOSurfaceLock(ioSurface, [], nil)
// ... レンダリング ...
IOSurfaceUnlock(ioSurface, [], nil)
```

---

## 推奨される実装順序

1. **まず修正版のCIContext実装を試す**（`bounds`を明示的に指定）
   - 最も簡単で、既存コードへの変更が少ない

2. **デバッグログで`ciImage.extent`を確認**
   - 問題の原因を特定

3. **テクスチャ内容の検証関数を追加**
   - レンダリング後のピクセルデータを確認

4. **それでも解決しない場合、Metal Compute Shaderに切り替え**
   - CoreImageの制約を完全に回避
   - パフォーマンスも向上する可能性

---

## 期待される結果

修正後、以下のような出力が得られるはずです：

```
🔍 CIImage.extent: (0.0, 0.0, 1280.0, 720.0)
   期待値: (0, 0, 1280, 720)

🔍 レンダリング後のテクスチャサンプル:
   左上 (0, 0): B=45, G=78, R=123, A=255
   中央 (640, 360): B=67, G=89, R=145, A=255
   右下 (1279, 719): B=89, G=112, R=167, A=255
   非ゼロピクセル: 921600 / 921600 (100.0%)
```

OBSで正常にカラー映像が表示されます。
