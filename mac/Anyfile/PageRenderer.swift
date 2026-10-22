// Draws a page turn with Metal: the next page flat, the turning page as a lit, bending sheet.
// The camera sits in front of the page so a page lying flat exactly fills the view; a page lifted
// toward the reader grows a little, as it would.
import Metal
import MetalKit
import CoreGraphics
import simd

struct PageUniforms {
    var viewProjection: simd_float4x4
    var paper: SIMD4<Float>
    var light: SIMD3<Float>
    var aspect: Float
    var shadow: Float
    var rows: Int32
}

final class PageRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pagePipeline: MTLRenderPipelineState
    private let flatPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let indexBuffer: MTLBuffer
    private let indexCount: Int
    private var turning: MTLTexture?, beneath: MTLTexture?
    private var aspect: Float = 1.4
    static let pixelFormat = MTLPixelFormat.bgra8Unorm
    /// How far the camera stands from the page, in page widths. Nearer exaggerates the lift.
    static let cameraDistance: Float = 3.4

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue(), let library = Self.library(device) else { return nil }
        self.device = device
        self.queue = queue
        func pipeline(_ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = Self.pixelFormat
            d.depthAttachmentPixelFormat = .depth32Float
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let page = pipeline("pageVertex", "pageFragment"), let flat = pipeline("flatVertex", "flatFragment") else { return nil }
        pagePipeline = page
        flatPipeline = flat
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)!
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: s)!
        let indices = PageGeometry.indices()
        indexCount = indices.count
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt32>.stride)!
    }

    /// The shaders, compiled once per device from source (see PageShaders for why not a .metal file).
    private static var compiled: [ObjectIdentifier: MTLLibrary] = [:]
    private static func library(_ device: MTLDevice) -> MTLLibrary? {
        let key = ObjectIdentifier(device)
        if let lib = compiled[key] { return lib }
        do {
            let lib = try device.makeLibrary(source: PageShaders.source, options: nil)
            compiled[key] = lib
            return lib
        } catch {
            NSLog("page turn shaders did not compile: %@", error.localizedDescription)
            return nil
        }
    }

    /// The page that turns, and the page that lies under it.
    func setPages(turning: CGImage, beneath: CGImage) {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [.SRGB: false, .textureStorageMode: MTLStorageMode.private.rawValue]
        self.turning = try? loader.newTexture(cgImage: turning, options: options)
        self.beneath = try? loader.newTexture(cgImage: beneath, options: options)
        aspect = Float(turning.height) / Float(max(turning.width, 1))
    }

    /// Draws the turn at `progress` (0 flat, 1 turned over) into `target`.
    func draw(progress: Float, into target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let turning, let beneath else { return }
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: target.width, height: target.height, mipmapped: false)
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private
        guard let depth = device.makeTexture(descriptor: depthDesc) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let verts = PageGeometry.vertices(progress: progress, aspect: aspect)
        let edge = PageGeometry.edge(progress: progress, aspect: aspect)
        var u = PageUniforms(viewProjection: Self.viewProjection(aspect: aspect), paper: Self.paper,
                             light: simd_normalize(SIMD3<Float>(-0.45, 0.5, 1)), aspect: aspect,
                             shadow: sin(.pi * progress), rows: Int32(PageGeometry.rows))
        enc.setDepthStencilState(depthState)
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.none)
        enc.setFragmentSamplerState(sampler, index: 0)

        enc.setRenderPipelineState(flatPipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<PageUniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<PageUniforms>.stride, index: 1)
        enc.setFragmentBytes(edge, length: edge.count * MemoryLayout<SIMD2<Float>>.stride, index: 2)
        enc.setFragmentTexture(beneath, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // setVertexBytes takes at most 4 KB; the sheet is about 59 KB, so it goes in a buffer of its
        // own each frame (a new one, so the GPU never reads a buffer the next frame is writing).
        guard let vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<PageVertex>.stride,
                                                   options: .storageModeShared) else { enc.endEncoding(); return }
        enc.setRenderPipelineState(pagePipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(turning, index: 0)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
        enc.endEncoding()
    }

    /// One frame as an image, drawn off-screen. Used by tests and for looking at frames.
    func image(progress: Float, width: Int, height: Int) -> CGImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: desc), let cb = queue.makeCommandBuffer() else { return nil }
        draw(progress: progress, into: target, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    /// The paper colour, in the same sRGB values the page images carry.
    static var paper: SIMD4<Float> {
        let c = Theme.paper.window.usingColorSpace(.sRGB) ?? .white
        return [Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1]
    }

    /// A camera centred on the page at `cameraDistance`, with a field of view that fits the page exactly.
    static func viewProjection(aspect: Float) -> simd_float4x4 {
        let d = cameraDistance, near: Float = 0.05, far: Float = 20
        let ys = d / (aspect / 2)                 // 1 / tan(half the vertical field of view)
        let xs = ys * aspect                      // the view is as wide as the page: width / height = 1 / aspect
        let zs = far / (near - far)
        let projection = simd_float4x4(columns: ([xs, 0, 0, 0], [0, ys, 0, 0], [0, 0, zs, -1], [0, 0, near * zs, 0]))
        let view = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [-0.5, -aspect / 2, -d, 1]))
        return projection * view
    }
}
