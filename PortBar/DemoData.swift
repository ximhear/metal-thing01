import Foundation

extension PortScanner {
    /// `--demo`용으로 지어낸 예시 목록. 이 Mac의 실제 프로세스나 경로는 하나도 들어가지 않는다.
    /// (README 스크린샷을 찍거나, 서버를 띄우지 않고 화면을 둘러볼 때 쓴다.)
    static func demoProcesses() -> [PortProcess] {
        let home = NSHomeDirectory()
        let tmp = (NSTemporaryDirectory() as NSString).standardizingPath
        let minute = 60.0, hour = 3600.0, day = 86400.0
        func ago(_ seconds: Double) -> Date { Date().addingTimeInterval(-seconds) }

        let shop = home + "/code/acme-shop"
        let blog = home + "/code/blog-api"
        let infra = home + "/code/infra"
        let notes = tmp + "/demo.Xk2a/notes-app"
        let node = "/opt/homebrew/bin/node"

        let list: [PortProcess] = [
            PortProcess(pid: 90001, ports: [3000], name: "node", command: "node next dev --port 3000",
                        executable: node, cwd: shop + "/web", startDate: ago(2 * hour), isSystem: false,
                        addresses: ["127.0.0.1", "[::1]"], projectRoot: shop, gitBranch: "feat/checkout"),
            PortProcess(pid: 90002, ports: [4000], name: "node", command: "node server.js",
                        executable: node, cwd: notes, startDate: ago(28 * day), isSystem: false,
                        addresses: ["*"], source: .missing(notes + "/server.js")),
            PortProcess(pid: 90003, ports: [5173], name: "node", command: "node vite --host 0.0.0.0 --port 5173",
                        executable: node, cwd: shop + "/apps/admin", startDate: ago(3 * day), isSystem: false,
                        addresses: ["*"], projectRoot: shop, gitBranch: "feat/checkout"),
            PortProcess(pid: 90004, ports: [5432], name: "postgres", command: "postgres -D postgresql@16",
                        executable: "/opt/homebrew/bin/postgres", cwd: "/opt/homebrew/var/postgresql@16",
                        startDate: ago(12 * day), isSystem: false, addresses: ["127.0.0.1", "[::1]"]),
            PortProcess(pid: 90005, ports: [8000], name: "Python", command: "Python -m uvicorn app.main:app --reload --port 8000",
                        executable: "/opt/homebrew/bin/python3", cwd: blog, startDate: ago(5 * hour), isSystem: false,
                        addresses: ["127.0.0.1"], source: .module("uvicorn"), projectRoot: blog, gitBranch: "main"),
            PortProcess(pid: 90006, ports: [8080], name: "kubectl", command: "kubectl port-forward svc/api 8080:80",
                        executable: "/opt/homebrew/bin/kubectl", cwd: infra, startDate: ago(40 * minute), isSystem: false,
                        addresses: ["127.0.0.1", "[::1]"], projectRoot: infra, gitBranch: "main"),
            PortProcess(pid: 90007, ports: [9000], name: "node", command: "node storybook dev -p 9000 --host 192.168.0.12",
                        executable: node, cwd: shop + "/packages/ui", startDate: ago(26 * hour), isSystem: false,
                        addresses: ["192.168.0.12"], projectRoot: shop, gitBranch: "feat/checkout"),

            PortProcess(pid: 90101, ports: [5000, 7000], name: "ControlCenter", command: "ControlCenter",
                        executable: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
                        cwd: "/", startDate: ago(34 * day), isSystem: true, addresses: ["*"]),
            PortProcess(pid: 90102, ports: [49152], name: "rapportd", command: "rapportd",
                        executable: "/usr/libexec/rapportd", cwd: "/", startDate: ago(34 * day), isSystem: true,
                        addresses: ["*"]),
            PortProcess(pid: 90103, ports: [52431], name: "Code Helper", command: "Code Helper --type=utility",
                        executable: "/Applications/Editor.app/Contents/MacOS/Code Helper", cwd: "/",
                        startDate: ago(6 * hour), isSystem: true, addresses: ["127.0.0.1"]),
        ]
        return list.sorted { ($0.isDevServer ? 0 : 1, $0.ports.first ?? 0) < ($1.isDevServer ? 0 : 1, $1.ports.first ?? 0) }
    }
}
