import MetalKit

/// Shaders.metal의 Uniforms와 같은 레이아웃 (24바이트).
struct Uniforms {
    var viewMin: SIMD2<Float>
    var scale: SIMD2<Float>
    var pointSize: Float
    var pad: Float = 0
}

/// 밀도 산점도: (1) 컴퓨트로 점마다 픽셀 카운터에 원자적 +1 → (2) 최대값 축소 → (3) 로그 컬러맵으로 화면에.
final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let splatPipeline: MTLComputePipelineState
    private let maxPipeline: MTLComputePipelineState
    private let colormapPipeline: MTLRenderPipelineState
    private let maxBuffer: MTLBuffer

    private var counts: MTLBuffer?
    private var countsSize = SIMD2<UInt32>(0, 0)
    private var pointBuffer: MTLBuffer?
    private var pointCount = 0
    private var uploadedVersion = -1

    weak var model: PlotModel?

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let maxBuffer = device.makeBuffer(length: 4, options: .storageModePrivate)
        else { return nil }
        self.device = device
        self.queue = queue
        self.maxBuffer = maxBuffer
        do {
            splatPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "splat")!)
            maxPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "maxReduce")!)
            let c = MTLRenderPipelineDescriptor()
            c.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            c.fragmentFunction = library.makeFunction(name: "colormapFragment")
            c.colorAttachments[0].pixelFormat = view.colorPixelFormat
            colormapPipeline = try device.makeRenderPipelineState(descriptor: c)
        } catch {
            print("Pipeline error: \(error)")
            return nil
        }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.needsDisplay = true
    }

    private func ensureCounts(width: Int, height: Int) -> MTLBuffer? {
        let size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        if let c = counts, countsSize == size { return c }
        countsSize = size
        counts = device.makeBuffer(length: width * height * 4, options: .storageModePrivate)
        return counts
    }

    private func uploadIfNeeded(_ model: PlotModel) {
        guard model.pointsVersion != uploadedVersion else { return }
        uploadedVersion = model.pointsVersion
        let pts = model.points
        pointCount = pts.count
        pointBuffer = pts.isEmpty ? nil : pts.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
    }

    func draw(in view: MTKView) {
        guard let model else { return }
        uploadIfNeeded(model)

        let w = Int(view.drawableSize.width), h = Int(view.drawableSize.height)
        guard w > 0, h > 0,
              let counts = ensureCounts(width: w, height: h),
              let passToScreen = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer()
        else { return }
        var size = countsSize
        var total = UInt32(w * h)

        // 0) 카운터·최대값 초기화
        if let blit = cb.makeBlitCommandEncoder() {
            blit.fill(buffer: counts, range: 0..<counts.length, value: 0)
            blit.fill(buffer: maxBuffer, range: 0..<4, value: 0)
            blit.endEncoding()
        }

        if let enc = cb.makeComputeCommandEncoder() {
            // 1) 점 찍기
            if let buf = pointBuffer, pointCount > 0 {
                let range = model.viewMax - model.viewMin
                var u = Uniforms(viewMin: SIMD2<Float>(model.viewMin),
                                 scale: SIMD2<Float>(2.0 / range),
                                 pointSize: 1)
                var n = UInt32(pointCount)
                enc.setComputePipelineState(splatPipeline)
                enc.setBuffer(buf, offset: 0, index: 0)
                enc.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.setBuffer(counts, offset: 0, index: 2)
                enc.setBytes(&size, length: 8, index: 3)
                enc.setBytes(&n, length: 4, index: 4)
                enc.dispatchThreads(MTLSize(width: pointCount, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: splatPipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1))
            }
            // 2) 최대값 축소
            enc.setComputePipelineState(maxPipeline)
            enc.setBuffer(counts, offset: 0, index: 0)
            enc.setBuffer(maxBuffer, offset: 0, index: 1)
            enc.setBytes(&total, length: 4, index: 2)
            enc.dispatchThreads(MTLSize(width: w * h, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: maxPipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1))
            enc.endEncoding()
        }

        // 3) 컬러맵으로 화면에
        passToScreen.colorAttachments[0].loadAction = .dontCare
        if let enc = cb.makeRenderCommandEncoder(descriptor: passToScreen) {
            enc.setRenderPipelineState(colormapPipeline)
            enc.setFragmentBuffer(counts, offset: 0, index: 0)
            enc.setFragmentBuffer(maxBuffer, offset: 0, index: 1)
            enc.setFragmentBytes(&size, length: 8, index: 2)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        cb.present(drawable)
        cb.addCompletedHandler { [weak model] cb in
            let ms = (cb.gpuEndTime - cb.gpuStartTime) * 1000
            DispatchQueue.main.async { model?.recordGPU(ms) }
        }
        cb.commit()
    }
}
