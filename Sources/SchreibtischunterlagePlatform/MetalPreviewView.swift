@preconcurrency import AppKit
@preconcurrency import CoreVideo
import Metal
import QuartzCore
import SchreibtischunterlageCore

public enum MetalPreviewViewError: Error, LocalizedError {
    case metalUnavailable
    case commandQueueUnavailable
    case textureCacheCreationFailed(CVReturn)
    case shaderLibraryCreationFailed
    case shaderFunctionMissing(String)

    public var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Metal is unavailable on this Mac."
        case .commandQueueUnavailable:
            return "Metal could not create a command queue."
        case let .textureCacheCreationFailed(status):
            return "Metal texture cache creation failed with status \(status)."
        case .shaderLibraryCreationFailed:
            return "Metal could not compile the preview shaders."
        case let .shaderFunctionMissing(name):
            return "Metal preview shader \(name) is missing."
        }
    }
}

private final class RetainedMetalTexture: @unchecked Sendable {
    let coreVideoTexture: CVMetalTexture
    let metalTexture: MTLTexture

    init(coreVideoTexture: CVMetalTexture, metalTexture: MTLTexture) {
        self.coreVideoTexture = coreVideoTexture
        self.metalTexture = metalTexture
    }
}

@MainActor
public final class MetalPreviewView: NSView {
    public var cursorPortalHandler: (@MainActor @Sendable (CGPoint) -> Void)?

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct PreviewVertex {
        float4 position [[position]];
        float2 textureCoordinate;
    };

    vertex PreviewVertex previewVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        const float2 textureCoordinates[] = {
            float2(0.0, 1.0),
            float2(2.0, 1.0),
            float2(0.0, -1.0)
        };

        PreviewVertex output;
        output.position = float4(positions[vertexID], 0.0, 1.0);
        output.textureCoordinate = textureCoordinates[vertexID];
        return output;
    }

    fragment half4 previewFragment(
        PreviewVertex input [[stage_in]],
        texture2d<half> sourceTexture [[texture(0)]],
        sampler sourceSampler [[sampler(0)]]
    ) {
        return sourceTexture.sample(sourceSampler, input.textureCoordinate);
    }
    """

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let textureCache: CVMetalTextureCache
    private let latencyTracker: PreviewLatencyTracker?
    private var cursorPortalActivationMode: CursorPortalActivationMode
    private var pendingClickLocation: CGPoint?

    public static func make() throws -> MetalPreviewView {
        try make(
            latencyTracker: nil,
            cursorPortalActivationMode: .singleClick
        )
    }

    static func make(
        latencyTracker: PreviewLatencyTracker?,
        cursorPortalActivationMode: CursorPortalActivationMode
    ) throws -> MetalPreviewView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalPreviewViewError.metalUnavailable
        }

        return try MetalPreviewView(
            device: device,
            latencyTracker: latencyTracker,
            cursorPortalActivationMode: cursorPortalActivationMode
        )
    }

    private init(
        device: MTLDevice,
        latencyTracker: PreviewLatencyTracker?,
        cursorPortalActivationMode: CursorPortalActivationMode
    ) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalPreviewViewError.commandQueueUnavailable
        }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(
                source: Self.shaderSource,
                options: nil
            )
        } catch {
            throw MetalPreviewViewError.shaderLibraryCreationFailed
        }
        guard let vertexFunction = library.makeFunction(name: "previewVertex") else {
            throw MetalPreviewViewError.shaderFunctionMissing("previewVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "previewFragment") else {
            throw MetalPreviewViewError.shaderFunctionMissing("previewFragment")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipelineState = try device.makeRenderPipelineState(
            descriptor: pipelineDescriptor
        )

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(
            descriptor: samplerDescriptor
        ) else {
            throw MetalPreviewViewError.metalUnavailable
        }

        var textureCache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        guard status == kCVReturnSuccess, let textureCache else {
            throw MetalPreviewViewError.textureCacheCreationFailed(status)
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.samplerState = samplerState
        self.textureCache = textureCache
        self.latencyTracker = latencyTracker
        self.cursorPortalActivationMode = cursorPortalActivationMode

        super.init(frame: .zero)

        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 2
        metalLayer.displaySyncEnabled = true
        metalLayer.presentsWithTransaction = false
        metalLayer.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    public override func layout() {
        super.layout()
        updateDrawableSize()
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        pendingClickLocation = convert(event.locationInWindow, from: nil)
    }

    public override func mouseUp(with event: NSEvent) {
        guard pendingClickLocation != nil else {
            return
        }

        pendingClickLocation = nil
        guard cursorPortalActivationMode.shouldActivate(
            clickCount: event.clickCount
        ) else {
            return
        }
        cursorPortalHandler?(convert(event.locationInWindow, from: nil))
    }

    public override func mouseDragged(with event: NSEvent) {
        cancelClickIfDragged(event)
    }

    func setCursorPortalActivationMode(
        _ mode: CursorPortalActivationMode
    ) {
        cursorPortalActivationMode = mode
        pendingClickLocation = nil
    }

    @discardableResult
    public func display(_ frame: CapturedFrame) -> Bool {
        updateDrawableSize()

        let sourceWidth = frame.width
        let sourceHeight = frame.height
        let drawableSize = metalLayer.drawableSize

        guard
            sourceWidth > 0,
            sourceHeight > 0,
            drawableSize.width > 0,
            drawableSize.height > 0
        else {
            latencyTracker?.recordRenderDrop(frame)
            return false
        }

        guard
            let drawable = metalLayer.nextDrawable(),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let texture = makeTexture(
                from: frame.pixelBuffer,
                width: sourceWidth,
                height: sourceHeight
            ),
            let viewport = AspectFitViewport(
                sourceWidth: Double(sourceWidth),
                sourceHeight: Double(sourceHeight),
                destinationWidth: drawableSize.width,
                destinationHeight: drawableSize.height
            )
        else {
            latencyTracker?.recordRenderDrop(frame)
            return false
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            latencyTracker?.recordRenderDrop(frame)
            return false
        }

        encoder.setViewport(
            MTLViewport(
                originX: viewport.originX,
                originY: viewport.originY,
                width: viewport.width,
                height: viewport.height,
                znear: 0,
                zfar: 1
            )
        )
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture.metalTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        let submissionTime = HostTimeClock.now
        latencyTracker?.recordSubmittedFrame(
            frame,
            at: submissionTime
        )
        drawable.addPresentedHandler { [latencyTracker] drawable in
            latencyTracker?.recordPresentation(
                frame: frame,
                submissionTime: submissionTime,
                presentationTime: drawable.presentedTime
            )
        }
        commandBuffer.addCompletedHandler { [latencyTracker] commandBuffer in
            latencyTracker?.recordGPUExecution(
                frame: frame,
                startTime: commandBuffer.gpuStartTime,
                endTime: commandBuffer.gpuEndTime
            )
            withExtendedLifetime(texture) {}
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        return true
    }

    private var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    private func cancelClickIfDragged(_ event: NSEvent) {
        guard let pendingClickLocation else {
            return
        }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(
            currentLocation.x - pendingClickLocation.x,
            currentLocation.y - pendingClickLocation.y
        )
        if distance > 4 {
            self.pendingClickLocation = nil
        }
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }

    private func makeTexture(
        from pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> RetainedMetalTexture? {
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &texture
        )
        guard
            status == kCVReturnSuccess,
            let texture,
            let metalTexture = CVMetalTextureGetTexture(texture)
        else {
            CVMetalTextureCacheFlush(textureCache, 0)
            return nil
        }

        return RetainedMetalTexture(
            coreVideoTexture: texture,
            metalTexture: metalTexture
        )
    }
}
