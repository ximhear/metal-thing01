import Foundation
import AppKit
import Observation

@Observable
final class PortModel {
    private(set) var processes: [PortProcess] = []
    private(set) var lastScan: Date?
    /// 종료 신호를 보냈지만 아직 살아 있는 pid → 강제 종료 버튼을 보여 준다.
    private(set) var stubborn: Set<Int32> = []
    private(set) var stopping: Set<Int32> = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var scanning = false

    var devProcesses: [PortProcess] { processes.filter(\.isDevServer) }
    var systemProcesses: [PortProcess] { processes.filter { !$0.isDevServer } }
    /// 다른 기기에서도 접속할 수 있는 개발 서버 수.
    var exposedCount: Int { devProcesses.filter(\.isExposed).count }

    /// 참이면 이 Mac을 훑지 않고 지어낸 예시 목록을 보여 준다. 종료 버튼도 신호를 보내지 않고 목록에서만 뺀다.
    @ObservationIgnored let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        refresh()
        if !demo {
            timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.refresh() }
        }
    }

    func refresh() {
        if demo {
            processes = PortScanner.demoProcesses()
            lastScan = Date()
            return
        }
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PortScanner.scan()
            DispatchQueue.main.async {
                self.processes = result
                self.lastScan = Date()
                let alive = Set(result.map(\.pid))
                self.stubborn.formIntersection(alive)
                self.stopping.formIntersection(alive)
                self.scanning = false
            }
        }
    }

    // MARK: 동작

    func openInBrowser(_ p: PortProcess, port: Int? = nil) {
        guard let port = port ?? p.ports.first, let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealFolder(_ p: PortProcess) {
        guard let cwd = p.cwd else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
    }

    /// 소스 파일은 열지 않고 Finder에서 보여 주기만 한다 (.jar·.py·.sh는 열면 실행될 수 있다).
    func revealSource(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyKillCommand(_ p: PortProcess) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("kill \(p.pid)", forType: .string)
    }

    /// SIGTERM을 보내고 1.5초 뒤에도 살아 있으면 강제 종료 버튼을 띄운다.
    func stop(_ p: PortProcess) {
        if demo { processes.removeAll { $0.pid == p.pid }; return }   // 예시 pid는 진짜 프로세스와 겹칠 수 있다
        guard kill(p.pid, SIGTERM) == 0 else { refresh(); return }
        stopping.insert(p.pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.stopping.remove(p.pid)
            if kill(p.pid, 0) == 0 { self.stubborn.insert(p.pid) }
            self.refresh()
        }
    }

    func forceStop(_ p: PortProcess) {
        if demo { processes.removeAll { $0.pid == p.pid }; return }
        kill(p.pid, SIGKILL)
        stubborn.remove(p.pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }
}
