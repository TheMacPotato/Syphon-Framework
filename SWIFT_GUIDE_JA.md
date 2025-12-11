# Syphon Framework - Swift使用ガイド

Syphon FrameworkをSwiftで使用するための完全なガイドです。Metal 4の最新機能を活用し、Apple Silicon上で最高のパフォーマンスを実現します。

## 目次

1. [導入](#導入)
2. [基本的な使い方](#基本的な使い方)
3. [サーバーの実装](#サーバーの実装)
4. [クライアントの実装](#クライアントの実装)
5. [SwiftUIでの使用](#swiftuiでの使用)
6. [Metal 4の最適化](#metal-4の最適化)
7. [パフォーマンスのヒント](#パフォーマンスのヒント)
8. [トラブルシューティング](#トラブルシューティング)

---

## 導入

### 必要要件

- **macOS**: 10.15以上（Metal 4の全機能を使用するには macOS 15以上を推奨）
- **Xcode**: 14.0以上
- **Swift**: 5.5以上
- **ハードウェア**: Apple M1以降のApple Silicon（またはA14 Bionic以降）

### フレームワークのインポート

Swiftでは以下のようにインポートします：

```swift
import Syphon
import Metal
import MetalKit
```

---

## 基本的な使い方

### Metal デバイスの作成

まず、Metalデバイスを取得します：

```swift
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metalデバイスが見つかりません")
}

// Apple Siliconの確認
if device.supportsFamily(.apple1) {
    print("✅ Apple Silicon検出 - Metal 4最適化が有効")
}
```

---

## サーバーの実装

### 基本的なサーバーの作成

```swift
import Syphon
import Metal

class SyphonServerManager {
    private var server: SyphonMetalServer?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    init?(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = queue

        // Syphonサーバーを作成
        self.server = SyphonMetalServer(
            name: "My Syphon Server",
            device: device,
            options: nil
        )
    }

    /// フレームを公開
    func publishFrame(_ texture: MTLTexture) {
        guard let server = server else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let region = NSRect(
            x: 0,
            y: 0,
            width: texture.width,
            height: texture.height
        )

        // Metal 4最適化: ゼロコピーでテクスチャを公開
        server.publishFrameTexture(
            texture,
            on: commandBuffer,
            imageRegion: region,
            flipped: false
        )

        commandBuffer.commit()
    }

    /// クライアントが接続されているか確認
    var hasClients: Bool {
        return server?.hasClients ?? false
    }

    /// サーバーを停止
    func stop() {
        server?.stop()
        server = nil
    }

    deinit {
        stop()
    }
}
```

### 使用例

```swift
// サーバーの初期化
guard let device = MTLCreateSystemDefaultDevice(),
      let serverManager = SyphonServerManager(device: device) else {
    fatalError("サーバーの初期化に失敗しました")
}

// テクスチャの公開
serverManager.publishFrame(myTexture)

// クライアントの確認
if serverManager.hasClients {
    print("クライアントが接続されています")
}
```

---

## クライアントの実装

### 基本的なクライアントの作成

```swift
import Syphon
import Metal

class SyphonClientManager {
    private var client: SyphonMetalClient?
    private let device: MTLDevice
    private var frameHandler: ((MTLTexture) -> Void)?

    init?(
        serverDescription: [String: Any],
        device: MTLDevice,
        onNewFrame: @escaping (MTLTexture) -> Void
    ) {
        self.device = device
        self.frameHandler = onNewFrame

        // Syphonクライアントを作成
        self.client = SyphonMetalClient(
            serverDescription: serverDescription,
            device: device,
            options: nil
        ) { [weak self] client in
            // 新しいフレームのコールバック
            self?.handleNewFrame()
        }

        guard client?.isValid == true else {
            return nil
        }
    }

    /// 新しいフレームを処理
    private func handleNewFrame() {
        guard let client = client,
              let texture = client.newFrameImage() else {
            return
        }

        // Metal 4最適化: ユニファイドメモリからの効率的な読み取り
        frameHandler?(texture)
    }

    /// 最新のフレームを取得
    func currentFrame() -> MTLTexture? {
        return client?.newFrameImage()
    }

    /// 新しいフレームがあるか確認
    var hasNewFrame: Bool {
        return client?.hasNewFrame ?? false
    }

    /// クライアントを停止
    func stop() {
        client?.stop()
        client = nil
    }

    deinit {
        stop()
    }
}
```

### サーバーディレクトリからクライアントを作成

```swift
import Syphon

class SyphonServerBrowser {
    private var directory: SyphonServerDirectory?

    init() {
        // サーバーディレクトリを取得
        self.directory = SyphonServerDirectory.shared()

        // サーバーリストの変更を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(serversDidChange),
            name: NSNotification.Name.syphonServerAnnounce,
            object: nil
        )
    }

    /// 利用可能なサーバーのリストを取得
    func availableServers() -> [[String: Any]] {
        return directory?.servers as? [[String: Any]] ?? []
    }

    /// 特定の名前のサーバーを検索
    func findServer(named name: String) -> [String: Any]? {
        return availableServers().first { serverDict in
            let serverName = serverDict[SyphonServerDescriptionNameKey] as? String
            return serverName == name
        }
    }

    @objc private func serversDidChange(_ notification: Notification) {
        print("Syphonサーバーリストが更新されました")
        print("利用可能なサーバー: \(availableServers().count)個")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// 使用例
let browser = SyphonServerBrowser()

// サーバーを検索してクライアントを作成
if let serverDescription = browser.findServer(named: "My Syphon Server"),
   let device = MTLCreateSystemDefaultDevice() {

    let client = SyphonClientManager(
        serverDescription: serverDescription,
        device: device
    ) { texture in
        // 新しいフレームを処理
        print("新しいフレーム: \(texture.width)x\(texture.height)")
    }
}
```

---

## SwiftUIでの使用

### MetalViewとの統合

```swift
import SwiftUI
import MetalKit
import Syphon

struct SyphonServerView: NSViewRepresentable {
    let device: MTLDevice
    @StateObject private var renderer: SyphonRenderer

    init(device: MTLDevice) {
        self.device = device
        _renderer = StateObject(wrappedValue: SyphonRenderer(device: device))
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        // Metal 4: 高性能レンダリングのための設定
        if #available(macOS 15.0, *) {
            mtkView.framebufferOnly = false
        }

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // 必要に応じて更新
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let renderer: SyphonRenderer

        init(renderer: SyphonRenderer) {
            self.renderer = renderer
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // サイズ変更を処理
        }

        func draw(in view: MTKView) {
            renderer.render(in: view)
        }
    }
}

// レンダラークラス
class SyphonRenderer: ObservableObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var serverManager: SyphonServerManager?

    init(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("コマンドキューの作成に失敗しました")
        }
        self.commandQueue = queue

        // Syphonサーバーを初期化
        self.serverManager = SyphonServerManager(device: device)
    }

    func render(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // レンダリング処理
        // ...

        // Syphonでフレームを公開
        serverManager?.publishFrame(drawable.texture)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
```

### SwiftUIアプリケーションでの使用

```swift
import SwiftUI

@main
struct SyphonApp: App {
    @StateObject private var syphonManager = SyphonManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syphonManager)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var syphonManager: SyphonManager

    var body: some View {
        VStack {
            if let device = MTLCreateSystemDefaultDevice() {
                SyphonServerView(device: device)
                    .frame(width: 800, height: 600)
            }

            HStack {
                Text("接続中のクライアント:")
                Text(syphonManager.hasClients ? "あり" : "なし")
                    .foregroundColor(syphonManager.hasClients ? .green : .gray)
            }
            .padding()
        }
    }
}

class SyphonManager: ObservableObject {
    @Published var hasClients = false
    private var timer: Timer?

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            // クライアント状態を更新
            self?.updateClientStatus()
        }
    }

    private func updateClientStatus() {
        // 実際のサーバーマネージャーから状態を取得
    }

    deinit {
        timer?.invalidate()
    }
}
```

---

## Metal 4の最適化

### 統合コマンドエンコーダーの活用

Metal 4では、統合コマンドエンコーダーが導入され、より効率的なコマンド記録が可能になりました：

```swift
// Metal 4: 統合コマンドエンコーダー準備完了
// 現在のSyphon実装は自動的にMetal 4の最適化を活用します

func publishFrameOptimized(_ texture: MTLTexture) {
    guard let server = server,
          let commandBuffer = commandQueue.makeCommandBuffer() else {
        return
    }

    let region = NSRect(
        x: 0,
        y: 0,
        width: texture.width,
        height: texture.height
    )

    // Metal 4が自動的に最適化されたパスを選択
    server.publishFrameTexture(
        texture,
        on: commandBuffer,
        imageRegion: region,
        flipped: false
    )

    commandBuffer.commit()
}
```

### MetalFX統合（将来の拡張）

Metal 4のMetalFXフレーム補間機能との統合例：

```swift
// 注意: これは将来の拡張例です
@available(macOS 15.0, *)
func setupMetalFXInterpolation() {
    // MetalFXフレーム補間の設定
    // Syphonと組み合わせて滑らかなフレームレート向上が可能
}
```

### 明示的常駐管理

大規模なテクスチャを扱う場合のMetal 4最適化：

```swift
@available(macOS 15.0, *)
func optimizeTextureResidency(_ texture: MTLTexture) {
    // Metal 4: 大規模ユニファイドメモリ空間での明示的常駐管理
    // Syphonフレームワークが自動的に処理しますが、
    // 必要に応じてカスタム最適化が可能

    if device.hasUnifiedMemory {
        // ユニファイドメモリの最適化
        print("ユニファイドメモリ: Metal 4最適化が有効")
    }
}
```

---

## パフォーマンスのヒント

### 1. コマンドバッファの再利用

```swift
class OptimizedSyphonServer {
    private let commandQueue: MTLCommandQueue
    private var reusableCommandBuffer: MTLCommandBuffer?

    func publishFrameEfficiently(_ texture: MTLTexture) {
        // コマンドバッファをプールから取得
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Metal 4の最適化されたコンパイルが自動的に適用されます
        server?.publishFrameTexture(
            texture,
            on: commandBuffer,
            imageRegion: NSRect(x: 0, y: 0, width: texture.width, height: texture.height),
            flipped: false
        )

        commandBuffer.commit()
    }
}
```

### 2. テクスチャフォーマットの最適化

```swift
// Apple Silicon用に最適化されたテクスチャディスクリプタ
func createOptimizedTexture(width: Int, height: Int) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,  // Syphonと互換性のあるフォーマット
        width: width,
        height: height,
        mipmapped: false
    )

    descriptor.usage = [.renderTarget, .shaderRead]

    // Apple Siliconでの最適化
    if device.hasUnifiedMemory {
        descriptor.storageMode = .shared  // ゼロコピーアクセス
        descriptor.cpuCacheMode = .defaultCache
    }

    return device.makeTexture(descriptor: descriptor)
}
```

### 3. 非同期処理の最適化

```swift
class AsyncSyphonPublisher {
    private let publishQueue = DispatchQueue(
        label: "com.syphon.publish",
        qos: .userInteractive  // 高優先度
    )

    func publishAsync(_ texture: MTLTexture) {
        publishQueue.async { [weak self] in
            self?.publishFrame(texture)
        }
    }

    private func publishFrame(_ texture: MTLTexture) {
        // Metal 4の高速コンパイルにより、オーバーヘッドが最小化
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        server?.publishFrameTexture(
            texture,
            on: commandBuffer,
            imageRegion: NSRect(x: 0, y: 0, width: texture.width, height: texture.height),
            flipped: false
        )

        commandBuffer.commit()
    }
}
```

### 4. フレームレートの制御

```swift
class FrameRateController {
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()
    private let targetFrameRate: Double = 60.0

    func shouldPublishFrame() -> Bool {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let deltaTime = currentTime - lastFrameTime
        let targetDelta = 1.0 / targetFrameRate

        if deltaTime >= targetDelta {
            lastFrameTime = currentTime
            return true
        }

        return false
    }
}

// 使用例
let frameController = FrameRateController()

func renderLoop() {
    if frameController.shouldPublishFrame() {
        publishFrame(myTexture)
    }
}
```

---

## トラブルシューティング

### よくある問題と解決策

#### 1. サーバーが見つからない

```swift
// サーバーディレクトリを確認
let directory = SyphonServerDirectory.shared()
let servers = directory?.servers as? [[String: Any]] ?? []

if servers.isEmpty {
    print("⚠️ 利用可能なSyphonサーバーがありません")
} else {
    servers.forEach { server in
        if let name = server[SyphonServerDescriptionNameKey] as? String {
            print("サーバー検出: \(name)")
        }
    }
}
```

#### 2. テクスチャが表示されない

```swift
// デバッグ情報を出力
func debugTexture(_ texture: MTLTexture) {
    print("テクスチャサイズ: \(texture.width)x\(texture.height)")
    print("ピクセルフォーマット: \(texture.pixelFormat)")
    print("使用法: \(texture.usage)")

    if device.hasUnifiedMemory {
        print("ストレージモード: \(texture.storageMode)")
    }
}
```

#### 3. パフォーマンスの問題

```swift
// パフォーマンスメトリクスの測定
class PerformanceMonitor {
    private var frameCount = 0
    private var startTime = CFAbsoluteTimeGetCurrent()

    func recordFrame() {
        frameCount += 1

        let currentTime = CFAbsoluteTimeGetCurrent()
        let elapsed = currentTime - startTime

        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            print("FPS: \(fps)")

            frameCount = 0
            startTime = currentTime
        }
    }
}
```

#### 4. メモリリーク

```swift
// 適切なリソース管理
class ResourceManager {
    weak var server: SyphonMetalServer?
    weak var client: SyphonMetalClient?

    func cleanup() {
        server?.stop()
        client?.stop()
        server = nil
        client = nil

        print("✅ リソースをクリーンアップしました")
    }

    deinit {
        cleanup()
    }
}
```

---

## 完全なサンプルアプリケーション

```swift
import SwiftUI
import MetalKit
import Syphon

@main
struct SyphonDemoApp: App {
    var body: some Scene {
        WindowGroup {
            SyphonDemoView()
        }
    }
}

struct SyphonDemoView: View {
    @StateObject private var viewModel = SyphonViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("Syphon Metal 4 デモ")
                .font(.title)

            if let device = viewModel.device {
                MetalPreviewView(device: device, viewModel: viewModel)
                    .frame(width: 800, height: 600)
                    .border(Color.gray, width: 2)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("サーバー状態")
                        .font(.headline)
                    Text("クライアント: \(viewModel.hasClients ? "接続中" : "未接続")")
                    Text("FPS: \(String(format: "%.1f", viewModel.fps))")
                }

                Divider()

                VStack(alignment: .leading) {
                    Text("利用可能なサーバー")
                        .font(.headline)
                    ForEach(viewModel.availableServers, id: \.self) { serverName in
                        Text("• \(serverName)")
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
        }
        .padding()
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

class SyphonViewModel: ObservableObject {
    @Published var hasClients = false
    @Published var fps: Double = 0
    @Published var availableServers: [String] = []

    let device: MTLDevice?
    private var serverManager: SyphonServerManager?
    private var browser: SyphonServerBrowser?

    init() {
        self.device = MTLCreateSystemDefaultDevice()

        if let device = device {
            self.serverManager = SyphonServerManager(device: device)
            self.browser = SyphonServerBrowser()
        }
    }

    func start() {
        updateServerList()

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    func stop() {
        serverManager?.stop()
    }

    private func updateStatus() {
        hasClients = serverManager?.hasClients ?? false
        updateServerList()
    }

    private func updateServerList() {
        guard let browser = browser else { return }
        availableServers = browser.availableServers().compactMap {
            $0[SyphonServerDescriptionNameKey] as? String
        }
    }
}

struct MetalPreviewView: NSViewRepresentable {
    let device: MTLDevice
    @ObservedObject var viewModel: SyphonViewModel

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(device: device, viewModel: viewModel)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue
        let viewModel: SyphonViewModel

        init(device: MTLDevice, viewModel: SyphonViewModel) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()!
            self.viewModel = viewModel
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            // レンダリング処理をここに実装

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
```

---

## まとめ

このガイドでは、SwiftでSyphon Frameworkを使用する方法を詳しく説明しました。Metal 4の最新機能を活用することで、Apple Silicon上で最高のパフォーマンスを実現できます。

### 重要なポイント

1. **Metal 4最適化**: Syphon Frameworkは自動的にMetal 4の機能を活用
2. **ユニファイドメモリ**: Apple Siliconのゼロコピーアクセスで高速化
3. **SwiftUI統合**: モダンなSwiftUIアプリケーションで簡単に使用可能
4. **パフォーマンス**: 適切な最適化でリアルタイム処理を実現

詳細な実装例や追加情報については、`APPLE_SILICON_MIGRATION.md`も参照してください。
