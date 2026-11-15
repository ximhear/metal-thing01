import SwiftUI
import AppKit

/// 화면 없이(잠금·디스플레이 꺼짐 상태에서도) 뷰를 PNG로 그린다. 스크린샷·디자인 비교용.
enum Snapshot {
    /// 포트 스캔이 한 번 끝난 모델을 돌려준다.
    static func scannedModel(demo: Bool = false) -> PortModel {
        let model = PortModel(demo: demo)
        let deadline = Date().addingTimeInterval(5)
        while model.lastScan == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return model
    }

    static func render<V: View>(_ view: V, to path: String, dark: Bool, settle: TimeInterval) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        app.appearance = appearance
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))   // onAppear·스크롤이 끝나기를 기다린다
        host.layoutSubtreeIfNeeded()

        let scale = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(2) }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
        do { try png.write(to: URL(fileURLWithPath: path)) } catch { print("write failed: \(error)"); exit(2) }
        print("snapshot \(path) \(Int(size.width))x\(Int(size.height))")
        exit(0)
    }
}
