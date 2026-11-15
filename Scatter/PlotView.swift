import SwiftUI
import MetalKit

struct PlotView: NSViewRepresentable {
    let model: PlotModel
    var onDropURL: (URL) -> Void

    final class Coordinator { var renderer: Renderer? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlotMTKView {
        let v = PlotMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm
        v.isPaused = true
        v.enableSetNeedsDisplay = true
        v.clearColor = MTLClearColor(red: 0.055, green: 0.06, blue: 0.075, alpha: 1)
        if let r = Renderer(view: v) {
            r.model = model
            v.delegate = r
            context.coordinator.renderer = r   // delegate는 weak라서 여기서 붙잡아 둔다
        }
        v.model = model
        v.onDropURL = onDropURL
        model.requestRedraw = { [weak v] in v?.needsDisplay = true }
        return v
    }

    func updateNSView(_ v: PlotMTKView, context: Context) {
        v.onDropURL = onDropURL
    }
}

/// 확대·이동·커서·파일 놓기를 처리하는 MTKView.
final class PlotMTKView: MTKView {
    weak var model: PlotModel?
    var onDropURL: ((URL) -> Void)?

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        registerForDraggedTypes([.fileURL])
    }
    required init(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    private func fraction(_ e: NSEvent) -> SIMD2<Double> {
        let p = convert(e.locationInWindow, from: nil)
        return SIMD2(Double(p.x / max(bounds.width, 1)), Double(p.y / max(bounds.height, 1)))
    }

    /// 화면 포인트 단위 이동. dx > 0: 내용이 오른쪽으로, dy > 0: 내용이 아래로.
    private func pan(dx: CGFloat, dy: CGFloat) {
        guard let m = model, bounds.width > 0, bounds.height > 0 else { return }
        let range = m.viewMax - m.viewMin
        let perPoint = SIMD2(range.x / Double(bounds.width), range.y / Double(bounds.height))
        m.pan(by: SIMD2(-Double(dx) * perPoint.x, Double(dy) * perPoint.y))
    }

    private func zoom(_ f: Double, _ e: NSEvent) {
        let mods = e.modifierFlags
        let fx = mods.contains(.shift) ? 1 : f     // ⇧: Y축만
        let fy = mods.contains(.option) ? 1 : f    // ⌥: X축만
        model?.zoom(factor: SIMD2(fx, fy), anchor: fraction(e))
    }

    override func scrollWheel(with e: NSEvent) {
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) {
            pan(dx: e.scrollingDeltaX, dy: e.scrollingDeltaY)
        } else {
            let delta = Double(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 1 : 8)
            zoom(pow(1.01, delta), e)
        }
        updateCursor(e)
    }

    override func magnify(with e: NSEvent) {
        zoom(1 + Double(e.magnification), e)
    }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { model?.fitAll() }
    }

    override func mouseDragged(with e: NSEvent) {
        pan(dx: e.deltaX, dy: e.deltaY)
        updateCursor(e)
    }

    override func mouseMoved(with e: NSEvent) { updateCursor(e) }
    override func mouseExited(with e: NSEvent) { model?.cursor = nil }

    private func updateCursor(_ e: NSEvent) {
        guard let m = model, m.pointCount > 0 else { return }
        let f = fraction(e)
        m.cursor = m.origin + m.viewMin + f * (m.viewMax - m.viewMin)
    }

    // MARK: 파일 놓기
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first else { return false }
        onDropURL?(url)
        return true
    }
}
