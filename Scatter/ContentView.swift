import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PlotModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260)
        } detail: {
            ZStack {
                PlotView(model: model) { model.open(url: $0) }
                if model.pointCount > 0 {
                    AxesOverlay(model: model)
                    CursorReadout(model: model)
                }
                if model.table == nil && !model.isLoading {
                    EmptyState()
                }
                if model.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("불러오는 중 · \(model.loadingName)")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { model.open(url: url) } }
                }
                return true
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.showImporter = true } label: { Label("열기", systemImage: "folder") }
                    .help("CSV 열기 (⌘O)")
                Button { model.fitAll() } label: { Label("전체 보기", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .help("전체 보기 (더블클릭)")
                    .disabled(model.pointCount == 0)
            }
        }
        .fileImporter(isPresented: $model.showImporter,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .data]) { result in
            if case .success(let url) = result { model.open(url: url) }
        }
        .alert("열 수 없어요", isPresented: Binding(get: { model.errorMessage != nil },
                                                set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .navigationTitle(model.table?.name ?? "Scatter")
        .frame(minWidth: 900, minHeight: 560)
    }
}

private struct EmptyState: View {
    @Environment(PlotModel.self) private var model
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.dots.scatter")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.6))
            Text("CSV 파일을 여기에 놓으세요")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("수천만 행도 GPU로 바로 그립니다")
                .foregroundStyle(.white.opacity(0.55))
            HStack {
                Button("파일 열기…") { model.showImporter = true }
                Button("예제 데이터 (1,000만 점)") { model.loadSynthetic() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
    }
}

private struct Sidebar: View {
    @Environment(PlotModel.self) private var model

    var body: some View {
        List {
            if let t = model.table {
                Section("파일") {
                    LabeledContent("이름", value: t.name)
                    LabeledContent("크기", value: ByteCountFormatter.string(fromByteCount: Int64(t.fileBytes), countStyle: .file))
                    LabeledContent("행", value: t.rowCount.formatted())
                    LabeledContent("불러오기", value: String(format: "%.2f초", t.loadSeconds))
                }
                Section("축") {
                    Picker("X", selection: Binding(get: { model.xColumn }, set: { model.setColumns(x: $0) })) {
                        Text("행 번호").tag(-1)
                        ForEach(t.numericColumns, id: \.self) { Text(t.columnNames[$0]).tag($0) }
                    }
                    Picker("Y", selection: Binding(get: { model.yColumn }, set: { model.setColumns(y: $0) })) {
                        ForEach(t.numericColumns, id: \.self) { Text(t.columnNames[$0]).tag($0) }
                    }
                }
                Section("렌더링") {
                    LabeledContent("그린 점", value: model.pointCount.formatted())
                    if model.invalidCount > 0 {
                        LabeledContent("건너뛴 행", value: model.invalidCount.formatted())
                    }
                    LabeledContent("GPU 프레임", value: model.gpuMs.map { String(format: "%.2f ms", $0) } ?? "–")
                }
            } else {
                Section {
                    Text("아직 연 파일이 없어요").foregroundStyle(.secondary)
                }
            }
            Section("조작") {
                ForEach(["드래그 · 두 손가락 스크롤: 이동", "핀치 · ⌘+스크롤 · 휠: 확대", "⌥ 누른 채: X축만 · ⇧: Y축만", "더블클릭: 전체 보기"], id: \.self) {
                    Text($0).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CursorReadout: View {
    let model: PlotModel
    var body: some View {
        let c = model.cursor
        VStack {
            Spacer()
            HStack {
                Spacer()
                if let c {
                    Text("x \(format(c.x))   y \(format(c.y))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.trailing, 10).padding(.bottom, 28)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 격자선과 눈금 라벨.
struct AxesOverlay: View {
    let model: PlotModel
    var body: some View {
        let vmin = model.viewMin, vmax = model.viewMax, o = model.origin
        Canvas { ctx, size in
            guard size.width > 0, size.height > 0, vmax.x > vmin.x, vmax.y > vmin.y else { return }
            let line = GraphicsContext.Shading.color(.white.opacity(0.09))
            let label = Color.white.opacity(0.65)

            let (xs, xStep) = niceTicks(lo: vmin.x + o.x, hi: vmax.x + o.x, target: Int(size.width / 110))
            for v in xs {
                let px = (v - o.x - vmin.x) / (vmax.x - vmin.x) * size.width
                if px < 40 || px > size.width - 30 { continue }   // 모서리 라벨 겹침 방지
                var p = Path(); p.move(to: CGPoint(x: px, y: 0)); p.addLine(to: CGPoint(x: px, y: size.height))
                ctx.stroke(p, with: line, lineWidth: 1)
                ctx.draw(Text(format(v, step: xStep)).font(.caption2.monospacedDigit()).foregroundStyle(label),
                         at: CGPoint(x: px, y: size.height - 6), anchor: .bottom)
            }
            let (ys, yStep) = niceTicks(lo: vmin.y + o.y, hi: vmax.y + o.y, target: Int(size.height / 70))
            for v in ys {
                let py = size.height - (v - o.y - vmin.y) / (vmax.y - vmin.y) * size.height
                if py > size.height - 24 || py < 16 { continue }
                var p = Path(); p.move(to: CGPoint(x: 0, y: py)); p.addLine(to: CGPoint(x: size.width, y: py))
                ctx.stroke(p, with: line, lineWidth: 1)
                ctx.draw(Text(format(v, step: yStep)).font(.caption2.monospacedDigit()).foregroundStyle(label),
                         at: CGPoint(x: 6, y: py - 2), anchor: .bottomLeading)
            }
        }
        .allowsHitTesting(false)
    }
}

func niceTicks(lo: Double, hi: Double, target: Int) -> ([Double], Double) {
    let span = hi - lo
    guard span > 0, span.isFinite else { return ([], 1) }
    let raw = span / Double(max(target, 2))
    let mag = pow(10, floor(log10(raw)))
    let n = raw / mag
    let step = (n < 1.5 ? 1 : n < 3 ? 2 : n < 7 ? 5 : 10) * mag
    var out: [Double] = []
    var v = ceil(lo / step) * step
    while v <= hi && out.count < 60 {
        out.append(v)
        v += step
    }
    return (out, step)
}

func format(_ v: Double, step: Double? = nil) -> String {
    if let step, abs(v) < step * 1e-6 { return "0" }
    return String(format: "%.6g", v)
}
