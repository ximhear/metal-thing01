import SwiftUI

@main
struct ScatterApp: App {
    @State private var model = PlotModel()

    init() {
        Bench.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onAppear {
                    // `--open <파일>` / `--synthetic`: 실행하자마자 불러오기 (테스트·명령줄용)
                    let args = CommandLine.arguments
                    if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
                        model.open(url: URL(fileURLWithPath: args[i + 1]))
                    } else if args.contains("--synthetic") {
                        model.loadSynthetic()
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("열기…") { model.showImporter = true }
                    .keyboardShortcut("o")
                Button("예제 데이터 (1,000만 점)") { model.loadSynthetic() }
            }
        }
    }
}

/// `Scatter --bench <파일.csv>`: 창 없이 불러오기 시간만 재고 종료.
enum Bench {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--bench"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1])
        do {
            let t = try CSVLoader.load(url: url)
            let valid = t.numericColumns.map { j in t.columns[j].reduce(0) { $1.isNaN ? $0 : $0 + 1 } }
            print(String(format: "rows=%d cols=%d numeric=%@ valid=%@ load=%.3fs",
                         t.rowCount, t.columns.count, t.numericColumns.description, valid.description, t.loadSeconds))
            exit(0)
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
    }
}
