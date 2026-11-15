import SwiftUI

@main
struct PortBarApp: App {
    // `--demo`: 이 Mac을 훑지 않고 지어낸 예시 목록을 보여 준다
    @State private var model = PortModel(demo: CommandLine.arguments.contains("--demo"))

    init() {
        // `PortBar --dump`: 창 없이 스캔 결과만 출력 (테스트용)
        if CommandLine.arguments.contains("--dump") {
            for p in PortScanner.scan() {
                print("\(p.isDevServer ? "dev" : "etc") pid=\(p.pid) ports=\(p.ports) title=\(p.title) addr=\(p.addresses.sorted()) fwd=\(p.forwarder ?? "-") cwd=\(p.cwd ?? "-") src=\(String(describing: p.source)) root=\(p.projectRoot ?? "-") branch=\(p.gitBranch ?? "-") cmd=\(p.command)")
            }
            exit(0)
        }
        // `--snapshot <png>`: 화면 없이 목록을 PNG로 (`--tall`, `--others`, `--dark`, `--demo-confirm`와 함께)
        // `--snapshot-label <png>`: 메뉴바 항목 모양
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let height = args.firstIndex(of: "--height").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
            let view = PortListView(listHeight: height.map { CGFloat($0) } ?? (args.contains("--tall") ? 780 : nil), expandOthers: args.contains("--others"),
                                    demoConfirm: args.contains("--demo-confirm"))
                .environment(Snapshot.scannedModel(demo: args.contains("--demo")))
            Snapshot.render(view, to: args[i + 1], dark: args.contains("--dark"), settle: args.contains("--others") ? 3.5 : 1)
        }
        if let i = args.firstIndex(of: "--snapshot-label"), i + 1 < args.count {
            let n = (args.contains("--demo") ? PortScanner.demoProcesses() : PortScanner.scan()).filter(\.isDevServer).count
            let label = HStack(spacing: 4) { Image(systemName: "server.rack"); Text(String(n)) }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Snapshot.render(label, to: args[i + 1], dark: args.contains("--dark"), settle: 0.3)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PortListView()
                .environment(model)
        } label: {
            let n = model.devProcesses.count
            // 지구본은 "외부 공개" 배지와 겹치고, 0개일 때 network.slash는 네트워크 끊김처럼 읽힌다.
            Image(systemName: "server.rack")
                .accessibilityLabel("PortBar, 개발 서버 \(n)개")
            if n > 0 { Text("\(n)") }
        }
        .menuBarExtraStyle(.window)

        // `--window`: 같은 내용을 일반 창으로 (스크린샷·디버깅용)
        // `--tall`: 목록을 길게, `--others`: "기타"를 펼쳐 그 위치로 스크롤, `--dark`: 다크 모드
        // `--demo-confirm`: 둘째 행을 종료 확인 상태로 (스크린샷용, 신호는 보내지 않는다)
        Window("PortBar", id: "debug") {
            let args = CommandLine.arguments
            PortListView(listHeight: args.contains("--tall") ? 780 : nil, expandOthers: args.contains("--others"),
                         demoConfirm: args.contains("--demo-confirm"))
                .environment(model)
                .preferredColorScheme(args.contains("--dark") ? .dark : nil)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(CommandLine.arguments.contains("--window") ? .presented : .suppressed)
    }
}
