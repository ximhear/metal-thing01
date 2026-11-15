import Foundation
import Observation

@Observable
final class PlotModel {
    var table: Table?
    private(set) var xColumn = 0     // -1: 행 번호
    private(set) var yColumn = 1

    /// GPU에는 (값 - origin)을 Float로 올린다. 큰 값(유닉스 시간 등)의 정밀도 손실을 줄이기 위함.
    private(set) var origin = SIMD2<Double>(0, 0)
    private(set) var dataMax = SIMD2<Double>(1, 1)   // origin 기준 상대값
    private(set) var viewMin = SIMD2<Double>(0, 0)
    private(set) var viewMax = SIMD2<Double>(1, 1)

    var cursor: SIMD2<Double>?
    private(set) var pointCount = 0
    private(set) var invalidCount = 0
    var gpuMs: Double?

    var isLoading = false
    var loadingName = ""
    var errorMessage: String?
    var showImporter = false

    @ObservationIgnored private(set) var points: [SIMD2<Float>] = []
    @ObservationIgnored private(set) var pointsVersion = 0
    @ObservationIgnored var requestRedraw: (() -> Void)?

    // MARK: 불러오기

    func open(url: URL) {
        startLoading(url.lastPathComponent) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try CSVLoader.load(url: url)
        }
    }

    func loadSynthetic() {
        startLoading("예제 데이터 (1,000만 점)") { CSVLoader.synthetic() }
    }

    private func startLoading(_ name: String, _ work: @escaping () throws -> Table) {
        guard !isLoading else { return }
        isLoading = true
        loadingName = name
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let t = try work()
                await MainActor.run { self.setTable(t) }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func setTable(_ t: Table) {
        table = t
        if t.numericColumns.count >= 2 {
            xColumn = t.numericColumns[0]
            yColumn = t.numericColumns[1]
        } else {
            xColumn = -1
            yColumn = t.numericColumns[0]
        }
        rebuildPoints()
        isLoading = false
        if CommandLine.arguments.contains("--gpu-bench") { runGPUBench() }
    }

    func setColumns(x: Int? = nil, y: Int? = nil) {
        if let x { xColumn = x }
        if let y { yColumn = y }
        rebuildPoints()
    }

    private func rebuildPoints() {
        guard let t = table else { return }
        let ys = t.columns[yColumn]
        let xs: [Double]? = xColumn >= 0 ? t.columns[xColumn] : nil
        let n = ys.count

        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        for i in 0..<n {
            let x = xs?[i] ?? Double(i), y = ys[i]
            if x.isNaN || y.isNaN { continue }
            lo = pointwiseMin(lo, SIMD2(x, y))
            hi = pointwiseMax(hi, SIMD2(x, y))
        }
        var pts: [SIMD2<Float>] = []
        if lo.x.isFinite {
            pts.reserveCapacity(n)
            for i in 0..<n {
                let x = xs?[i] ?? Double(i), y = ys[i]
                if x.isNaN || y.isNaN { continue }
                pts.append(SIMD2(Float(x - lo.x), Float(y - lo.y)))
            }
            origin = lo
            dataMax = hi - lo
        }
        points = pts
        pointCount = pts.count
        invalidCount = n - pts.count
        pointsVersion += 1
        fitAll()
    }

    // MARK: GPU 시간

    @ObservationIgnored private var benchSamples: [Double] = []
    @ObservationIgnored private var benchTimer: Timer?

    func recordGPU(_ ms: Double) {
        gpuMs = ms
        if benchTimer != nil { benchSamples.append(ms) }
    }

    /// `--gpu-bench`: 확대·이동을 흉내 내며 120프레임 GPU 시간을 재고 출력한 뒤 종료.
    func runGPUBench() {
        var step = 0
        benchTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            guard let self else { return }
            step += 1
            if step <= 60 {
                self.zoom(factor: SIMD2(1.04, 1.04), anchor: SIMD2(0.45, 0.55))
            } else {
                self.pan(by: (self.viewMax - self.viewMin) * SIMD2(0.01, 0.004))
            }
            if self.benchSamples.count >= 120 {
                t.invalidate()
                let s = self.benchSamples.dropFirst(5).sorted()
                let avg = s.reduce(0, +) / Double(s.count)
                print(String(format: "gpu frames=%d avg=%.2fms p50=%.2fms p95=%.2fms max=%.2fms points=%d",
                             s.count, avg, s[s.count / 2], s[Int(Double(s.count) * 0.95)], s.last!, self.pointCount))
                exit(0)
            }
        }
    }

    // MARK: 보기 범위

    func fitAll() {
        var span = dataMax
        if span.x <= 0 { span.x = 1 }
        if span.y <= 0 { span.y = 1 }
        let pad = span * 0.04
        viewMin = -pad
        viewMax = SIMD2(max(dataMax.x, 0), max(dataMax.y, 0)) + pad + (dataMax.x <= 0 || dataMax.y <= 0 ? pad : .zero)
        requestRedraw?()
    }

    func pan(by d: SIMD2<Double>) {
        viewMin += d
        viewMax += d
        requestRedraw?()
    }

    /// factor > 1: 확대. anchor: 화면에서의 위치(0~1).
    func zoom(factor: SIMD2<Double>, anchor: SIMD2<Double>) {
        let range = viewMax - viewMin
        let a = viewMin + anchor * range
        var newRange = range / factor
        let minRange = pointwiseMax(dataMax, SIMD2(1e-9, 1e-9)) * 1e-6   // Float 정밀도 한계
        newRange = pointwiseMax(newRange, minRange)
        viewMin = a - anchor * newRange
        viewMax = viewMin + newRange
        requestRedraw?()
    }
}
