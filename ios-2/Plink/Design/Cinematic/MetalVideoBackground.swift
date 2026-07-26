//
//  MetalVideoBackground.swift
//  Plink
//
//  Background video player for Plink+ live themes.
//  NO AVPlayer — uses AVAssetReader + VideoToolbox to decode frames in the
//  background, then renders them via Metal (MTKView). Completely isolated
//  from AVAudioSession, so it never conflicts with the main movie player.
//
//  Why this exists:
//    AVPlayer instances fight over AVAudioSession + hardware decoder on iOS.
//    Background video via AVPlayer crashes or shows black screen when the
//    movie player is also active. This component decodes video manually
//    and paints pixels to a Metal layer — no AVPlayer, no audio session,
//    no resource contention.
//
//  Looping: seamless — when AVAssetReader reaches end, we re-create the
//  reader and continue from frame 0. A small ring buffer (3 frames) keeps
//  the render thread fed without blocking.
//
//  Memory: frames are decoded on a background queue, converted to MTLTextures
//  with .shared storage mode, and recycled. Peak memory = 3 frames × 1080×1920
//  BGRA = ~25 MB. Frames are released when the view disappears.
//
//  Battery: VideoToolbox uses hardware decode; CPU usage is minimal.
//  CADisplayLink (driven by MTKView) only renders when the view is onscreen.
//

import SwiftUI
import AVFoundation
import Metal       // explicitly import Metal so MTLSamplerStateDescriptor / .linear / .clampToEdge are visible
import MetalKit
import Combine

// MARK: - SwiftUI entry point

struct MetalVideoBackground: View {
    let videoName: String          // e.g. "live_theme_1" (looks in LiveThemes/ subdir or top-level)
    var opacity: Double = 0.35     // background tint strength
    var overlayColor: Color = .black
    var overlayOpacity: Double = 0.4
    /// When true, black pixels in the video become transparent (alpha=0).
    /// Used for AI orb videos that have neon on black — only the neon shows.
    /// Implemented as: alpha = max(r, max(g, b)) in the fragment shader.
    var transparentBlack: Bool = false

    var body: some View {
        MetalVideoBackgroundRepresentable(
            videoName: videoName,
            opacity: opacity,
            overlayColor: overlayColor,
            overlayOpacity: overlayOpacity,
            transparentBlack: transparentBlack
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - UIViewRepresentable wrapping MTKView

struct MetalVideoBackgroundRepresentable: UIViewRepresentable {
    let videoName: String
    let opacity: Double
    let overlayColor: Color
    let overlayOpacity: Double
    let transparentBlack: Bool

    func makeUIView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.isOpaque = false
        view.backgroundColor = .clear
        view.framebufferOnly = false  // CRITICAL: must be false for transparent background
        view.preferredFramesPerSecond = 45  // 45 FPS — smooth but battery-friendly
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
        view.contentMode = .scaleAspectFit  // Don't stretch video

        let renderer = MetalVideoRenderer(
            device: device!, view: view, videoName: videoName,
            transparentBlack: transparentBlack
        )
        view.delegate = renderer
        context.coordinator.renderer = renderer
        renderer.start()
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Apply opacity changes live — the renderer reads its `tintOpacity` each frame.
        context.coordinator.renderer?.tintOpacity = Float(opacity)
        context.coordinator.renderer?.overlayOpacity = Float(overlayOpacity)
        context.coordinator.renderer?.transparentBlack = transparentBlack
        // Pass overlay color as SIMD4<Float> (16 bytes) — matches the float4
        // argument in the Metal fragment shader. float3 would be padded to
        // 16 bytes by Metal's std140 layout, causing a size mismatch crash.
        let uiColor = UIColor(overlayColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        context.coordinator.renderer?.overlayRGB = SIMD4<Float>(Float(r), Float(g), Float(b), 1.0)

        // If the video name changed (theme switch), reload the renderer with
        // the new video. Without this, the renderer keeps playing the OLD
        // video even after SwiftUI updates the videoName prop.
        if context.coordinator.renderer?.currentVideoName != videoName {
            context.coordinator.renderer?.loadNewVideo(videoName)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.renderer?.stop()
    }

    final class Coordinator {
        var renderer: MetalVideoRenderer?
    }
}

// MARK: - Metal renderer + frame decoder

final class MetalVideoRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private weak var view: MTKView?

    /// Current video name (mutable so we can hot-swap videos on theme switch).
    private(set) var currentVideoName: String
    private var assetReader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?
    private var videoTrack: AVAssetReaderTrackOutput?
    private var videoURL: URL?
    private let decodeQueue = DispatchQueue(label: "plink.metalvideo.decode", qos: .utility)

    // Ring buffer of decoded textures — keeps render thread fed.
    private var frameBuffer: [MTLTexture] = []
    private let bufferSize = 4   // smaller buffer = less memory, faster swap
    private var writeIndex = 0
    private var readIndex = 0
    private var framesAvailable = 0
    private let bufferLock = NSLock()

    // Last decoded frame — render always has something to show, even when
    // the ring buffer is momentarily empty (during reader restart).
    private var lastFrame: MTLTexture?
    private let lastFrameLock = NSLock()

    // Pipeline state
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    // No sampler property — inline sampler in fragment shader.

    // Tint / overlay (read every frame from SwiftUI)
    var tintOpacity: Float = 0.35
    var overlayOpacity: Float = 0.4
    // SIMD4<Float> (16 bytes) — matches float4 in Metal fragment shader.
    // Using a tuple (12 bytes) caused a Metal validation crash because
    // Metal pads float3 to 16 bytes per std140 layout.
    var overlayRGB: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)
    /// When true, alpha = max(r, max(g, b)) — black pixels become transparent.
    /// Set from SwiftUI via updateUIView.
    var transparentBlack: Bool = false

    // Decoder state
    private var isDecoding = false
    private var isStopped = false

    init(device: MTLDevice, view: MTKView, videoName: String, transparentBlack: Bool = false) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.view = view
        self.currentVideoName = videoName
        self.transparentBlack = transparentBlack
        super.init()
        setupPipeline()
        loadVideoURL()
    }

    // MARK: - Pipeline setup (fullscreen triangle)

    private func setupPipeline() {
        // Shader source compiled at runtime — no .metallib file needed.
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
            // Fullscreen triangle: 3 vertices cover the screen.
            float2 positions[3] = {
                float2(-1, -1),
                float2( 3, -1),
                float2(-1,  3)
            };
            float2 p = positions[vertexID];
            VertexOut out;
            out.position = float4(p, 0, 1);
            out.uv = float2((p.x + 1) * 0.5, 1 - (p.y + 1) * 0.5);
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                       texture2d<float> videoTexture [[texture(0)]],
                                       constant float& tintOpacity [[buffer(0)]],
                                       constant float& overlayOpacity [[buffer(1)]],
                                       constant float4& overlayRGB [[buffer(2)]],
                                       constant float& transparentBlack [[buffer(3)]]) {
            // Inline sampler — no need for MTLSamplerStateDescriptor from Swift.
            sampler videoSampler(coord::normalized, filter::linear, address::clamp_to_edge);
            float4 video = videoTexture.sample(videoSampler, in.uv);
            // Apply tint opacity — blend video with black at tintOpacity strength.
            float3 color = video.rgb * tintOpacity;
            // Add overlay color (default black) to dim the video further.
            // overlayRGB is float4 (16 bytes) to match Metal's std140 layout —
            // float3 would be padded to 16 bytes anyway, causing a size mismatch.
            color = mix(color, overlayRGB.rgb, overlayOpacity);

            // Alpha: when transparentBlack > 0.5, black pixels become transparent.
            // alpha = max(r, max(g, b)) scaled by tintOpacity — bright neon
            // stays opaque, dark background fades to 0. Used for AI orb videos.
            float alpha = 1.0;
            if (transparentBlack > 0.5) {
                float brightness = max(color.r, max(color.g, color.b));
                alpha = clamp(brightness * 1.5, 0.0, 1.0);
            }
            return float4(color, alpha);
        }
        """
        let library2 = try? device.makeLibrary(source: shaderSource, options: nil)
        guard let lib = library2,
              let vertexFn = lib.makeFunction(name: "vertex_main"),
              let fragmentFn = lib.makeFunction(name: "fragment_main") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
        // No MTLSamplerStateDescriptor needed — the fragment shader creates
        // an inline sampler (filter::linear, address::clamp_to_edge).
    }

    // MARK: - Video URL discovery

    private func loadVideoURL() {
        // Try subdirectory first (Resources/LiveThemes/)
        if let url = Bundle.main.url(forResource: currentVideoName, withExtension: "mp4", subdirectory: "LiveThemes") {
            videoURL = url
            return
        }
        // Try top-level bundle
        if let url = Bundle.main.url(forResource: currentVideoName, withExtension: "mp4") {
            videoURL = url
        }
    }

    /// Hot-swap to a new video without recreating the MTKView.
    /// Called from updateUIView when videoName changes.
    func loadNewVideo(_ name: String) {
        // Stop current decode, clear buffers, load new URL, restart.
        isStopped = true
        assetReader?.cancelReading()
        assetReader = nil
        trackOutput = nil
        videoTrack = nil
        bufferLock.lock()
        frameBuffer.removeAll()
        framesAvailable = 0
        writeIndex = 0
        readIndex = 0
        bufferLock.unlock()
        lastFrameLock.lock()
        lastFrame = nil
        lastFrameLock.unlock()

        currentVideoName = name
        loadVideoURL()
        isStopped = false
        isDecoding = false
        beginDecoding()
    }

    // MARK: - Start / stop

    func start() {
        guard videoURL != nil else { return }
        isStopped = false
        beginDecoding()
    }

    func stop() {
        isStopped = true
        assetReader?.cancelReading()
        assetReader = nil
        trackOutput = nil
        videoTrack = nil
        bufferLock.lock()
        frameBuffer.removeAll()
        framesAvailable = 0
        bufferLock.unlock()
        lastFrameLock.lock()
        lastFrame = nil
        lastFrameLock.unlock()
    }

    // MARK: - Decode loop (background thread)

    private func beginDecoding() {
        guard !isDecoding, !isStopped, let url = videoURL else { return }
        isDecoding = true
        decodeQueue.async { [weak self] in
            self?.decodeLoop(url: url)
        }
    }

    private func decodeLoop(url: URL) {
        while !isStopped {
            // (Re)create reader for this loop iteration.
            let asset = AVURLAsset(url: url)
            guard let reader = try? AVAssetReader(asset: asset) else {
                isDecoding = false
                return
            }

            // iOS 16+ deprecates `asset.tracks(withMediaType:)`. Use the
            // async loadTracks API and bridge to synchronous with a semaphore.
            // Falls back to the legacy sync API on older iOS for compatibility.
            let track: AVAssetTrack?
            if #available(iOS 16, *) {
                let semaphore = DispatchSemaphore(value: 0)
                var loadedTrack: AVAssetTrack?
                Task {
                    if let tracks = try? await asset.loadTracks(withMediaType: .video) {
                        loadedTrack = tracks.first
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                track = loadedTrack
            } else {
                // Legacy sync API — deprecated in iOS 16 but still works.
                track = asset.tracks(withMediaType: .video).first
            }
            guard let track else {
                isDecoding = false
                return
            }

            // Request BGRA32 output — directly compatible with MTLTexture.
            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            reader.startReading()

            self.assetReader = reader
            self.trackOutput = output

            while reader.status == .reading && !isStopped {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    // Convert CVPixelBuffer → MTLTexture
                    if let texture = makeTexture(from: pixelBuffer) {
                        // Update lastFrame so render always has something to show
                        // even when the ring buffer is momentarily empty.
                        lastFrameLock.lock()
                        lastFrame = texture
                        lastFrameLock.unlock()
                        enqueueFrame(texture)
                    }
                }
                // Pace decode to ~30fps to match the video's native frame rate.
                // Without this, copyNextSampleBuffer decodes ALL 180 frames in
                // <1s, render consumes them at 60fps → video plays at ~10x speed
                // and appears to "loop" rapidly. 1/30s sleep keeps decode in sync
                // with the video's intended playback rate.
                Thread.sleep(forTimeInterval: 1.0 / 45.0)
            }

            reader.cancelReading()
            self.assetReader = nil
            self.trackOutput = nil
            // Loop: while loop will re-create the reader and start from frame 0.
        }
        isDecoding = false
    }

    /// Convert CVPixelBuffer → MTLTexture.
    ///
    /// IMPORTANT: We ALWAYS copy bytes into a fresh MTLTexture. The IOSurface
    /// fast path (makeTexture(descriptor:iosurface:plane:)) wraps the pixel
    /// buffer's IOSurface directly, but AVAssetReaderTrackOutput with
    /// alwaysCopiesSampleData=false RECYCLES pixel buffers — when the decode
    /// loop calls copyNextSampleBuffer() again, the previous IOSurface is
    /// invalidated. If the render thread samples a texture backed by a dead
    /// IOSurface, we get EXC_BAD_ACCESS (code=1, address=0x0).
    ///
    /// The byte copy is ~1ms per 720x1280 frame — negligible at 30fps decode.
    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        return makeTextureByCopying(pixelBuffer: pixelBuffer, width: width, height: height)
    }

    /// Fallback texture creation: lock pixel buffer, copy bytes into a fresh MTLTexture.
    private func makeTextureByCopying(pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: baseAddress,
            bytesPerRow: bytesPerRow
        )
        return texture
    }

    // MARK: - Frame ring buffer

    private func enqueueFrame(_ texture: MTLTexture) {
        bufferLock.lock()
        // Drop frame if buffer is full — keeps decode thread from running ahead.
        if framesAvailable >= bufferSize {
            bufferLock.unlock()
            return
        }
        if writeIndex < frameBuffer.count {
            frameBuffer[writeIndex] = texture
        } else {
            frameBuffer.append(texture)
        }
        writeIndex = (writeIndex + 1) % bufferSize
        framesAvailable += 1
        bufferLock.unlock()
    }

    private func dequeueFrame() -> MTLTexture? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard framesAvailable > 0, readIndex < frameBuffer.count else { return nil }
        let texture = frameBuffer[readIndex]
        readIndex = (readIndex + 1) % bufferSize
        framesAvailable -= 1
        return texture
    }

    // MARK: - MTKViewDelegate (render loop)

    func draw(in view: MTKView) {
        guard let pipelineState,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        // Clear to transparent — without this, MTKView renders opaque black
        // background even with isOpaque=false and backgroundColor=.clear.
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        encoder.setRenderPipelineState(pipelineState)
        // No setFragmentSamplerState — fragment shader uses inline sampler.

        // Pull latest decoded frame. If the ring buffer is empty (reader
        // restart gap), fall back to lastFrame so we never show nothing.
        var currentTexture: MTLTexture?
        if let texture = dequeueFrame() {
            currentTexture = texture
        } else {
            lastFrameLock.lock()
            currentTexture = lastFrame
            lastFrameLock.unlock()
        }
        if let texture = currentTexture {
            encoder.setFragmentTexture(texture, index: 0)
        }

        // Tint + overlay uniforms
        var tint = tintOpacity
        var overlay = overlayOpacity
        var rgb = overlayRGB
        var transparent = transparentBlack ? Float(1.0) : Float(0.0)
        encoder.setFragmentBytes(&tint, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentBytes(&overlay, length: MemoryLayout<Float>.size, index: 1)
        // 16 bytes — matches float4 in fragment shader (SIMD4<Float>).
        encoder.setFragmentBytes(&rgb, length: MemoryLayout<SIMD4<Float>>.size, index: 2)
        encoder.setFragmentBytes(&transparent, length: MemoryLayout<Float>.size, index: 3)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No-op — fullscreen triangle scales automatically.
    }
}

// MARK: - APNG fallback (Variant 2)
// UIImageView.animationImages for theme preview cards — low-memory if frames are downscaled.
// Use this for small preview thumbnails where Metal would be overkill.

struct APNGThemePreview: View {
    let framePrefix: String        // e.g. "live_theme_1_frame"
    let frameCount: Int            // number of frames
    let frameDuration: Double      // seconds per frame
    var size: CGFloat = 112

    var body: some View {
        APNGPreviewRepresentable(
            framePrefix: framePrefix,
            frameCount: frameCount,
            frameDuration: frameDuration,
            size: size
        )
    }
}

struct APNGPreviewRepresentable: UIViewRepresentable {
    let framePrefix: String
    let frameCount: Int
    let frameDuration: Double
    let size: CGFloat

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.frame = CGRect(x: 0, y: 0, width: size, height: size * 1.34)
        iv.layer.cornerRadius = 20
        iv.backgroundColor = .black

        // Load frames lazily — only what fits in memory.
        var images: [UIImage] = []
        images.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            let name = String(format: "\(framePrefix)_%03d", i)
            if let img = UIImage(named: name) {
                images.append(img)
            }
        }
        iv.animationImages = images
        iv.animationDuration = Double(frameCount) * frameDuration
        iv.animationRepeatCount = 0  // infinite
        iv.startAnimating()
        return iv
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    static func dismantleUIView(_ uiView: UIImageView, coordinator: ()) {
        uiView.stopAnimating()
        uiView.animationImages = nil
    }
}
