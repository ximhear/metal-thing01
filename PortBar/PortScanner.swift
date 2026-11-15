import Foundation
import Darwin

/// TCP 포트를 열고 대기 중인 프로세스 하나.
struct PortProcess: Identifiable, Hashable {
    let pid: Int32
    var ports: [Int]
    var name: String          // 실행 파일 이름
    var command: String       // 줄인 명령줄
    var executable: String?   // 실행 파일 전체 경로
    var cwd: String?          // 작업 폴더
    var startDate: Date?
    var isSystem: Bool
    var addresses: Set<String> = []   // 대기 중인 주소: "127.0.0.1", "*", "[::1]", "192.168.0.5" …
    var source: Source?               // 명령에서 찾은 소스 파일 또는 모듈
    var projectRoot: String?          // 실행 위치에서 위로 찾은 .git 폴더의 부모
    var gitBranch: String?

    enum Source: Hashable {
        case file(String)     // 전체 경로
        case module(String)   // python -m 모듈
        case missing(String)  // 명령에는 있지만 지금은 지워진 파일
    }

    var id: Int32 { pid }

    enum Exposure { case loopback, network, specific(String) }

    /// 누가 접속할 수 있나: 이 Mac만(루프백) / 모든 네트워크 / 특정 주소.
    var exposure: Exposure {
        let nonLoop = addresses.filter { !PortScanner.isLoopback($0) }
        if nonLoop.isEmpty { return .loopback }
        if nonLoop.contains(where: { $0 == "*" || $0 == "0.0.0.0" || $0 == "[::]" }) { return .network }
        return .specific(nonLoop.sorted().joined(separator: ", "))
    }

    /// 이 Mac에서 직접 돈 서버가 아니라, 다른 곳의 포트를 연결해 준 것.
    var forwarder: String? {
        switch name {
        case "ssh": return "SSH 터널"
        case "kubectl": return "kubectl 포워딩"
        case "com.docker.backend", "vpnkit-bridge", "docker-proxy", "com.docker.vpnkit": return "Docker"
        case "cloudflared", "ngrok", "socat", "colima", "limactl", "ssh-agent": return "포워딩"
        default: return nil
        }
    }

    /// 개발 서버로 보는 기준: 시스템·앱 번들이 아니고, 임시 포트(49152~)가 아닌 포트를 하나라도 연다.
    var isDevServer: Bool { !isSystem && ports.contains { $0 < 49152 } }

    /// 목록에 크게 보일 이름: 작업 폴더 이름, 없으면 실행 파일 이름.
    var title: String {
        if let cwd, cwd != "/", cwd != NSHomeDirectory() { return (cwd as NSString).lastPathComponent }
        return name
    }

    /// 루프백이 아닌 주소에서도 대기 중인가 (같은 네트워크의 다른 기기가 접속할 수 있다).
    var isExposed: Bool {
        if case .loopback = exposure { return false }
        return true
    }

    /// git 저장소 안에서 실행했으면 저장소 폴더 이름.
    var projectName: String? { projectRoot.map { ($0 as NSString).lastPathComponent } }

    /// 저장소 루트 아래의 상대 경로. 루트에서 바로 실행했으면 nil.
    var projectSubpath: String? {
        guard let root = projectRoot, let cwd, cwd.hasPrefix(root + "/") else { return nil }
        return String(cwd.dropFirst(root.count + 1))
    }

    /// 제목 옆에 붙일 위치 표시: "› frontend", 더 깊으면 "› … › frontend". 전체 경로는 경로 줄에 있다.
    var projectCrumb: String? {
        guard let parts = projectSubpath?.split(separator: "/"), let last = parts.last else { return nil }
        return parts.count > 1 ? "› … › \(last)" : "› \(last)"
    }

    /// 일주일 넘게 켜져 있는 개발 서버. DB·캐시처럼 원래 계속 켜 두는 것은 뺀다.
    var isStale: Bool {
        guard isDevServer, !isKnownNonHTTP, let startDate else { return false }
        return Date().timeIntervalSince(startDate) >= 7 * 86400
    }

    /// 작업 폴더가 `/`나 홈이면 위치로서 알려 주는 것이 없다.
    var hasInformativeFolder: Bool {
        guard let cwd else { return false }
        return cwd != "/" && cwd != NSHomeDirectory()
    }

    private static let nonHTTPNames: Set<String> = ["mysqld", "redis-server", "adb", "postgres", "mongod", "memcached"]
    private static let nonHTTPPorts: Set<Int> = [22, 3306, 5037, 5432, 6379, 11211, 27017]

    /// DB·캐시·adb처럼 브라우저로 열어도 볼 것이 없는 서버.
    var isKnownNonHTTP: Bool {
        Self.nonHTTPNames.contains(name) || (ports.first.map(Self.nonHTTPPorts.contains) ?? false)
    }

    /// 브라우저로 열 만한 개발 서버인가.
    var looksLikeWebServer: Bool { isDevServer && !isKnownNonHTTP }
}

enum PortScanner {
    /// `lsof`로 LISTEN 중인 TCP 포트를 모으고, 프로세스 정보는 libproc·sysctl로 채운다.
    static func scan() -> [PortProcess] {
        let output = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"])
        var ports: [Int32: Set<Int>] = [:]
        var addrs: [Int32: Set<String>] = [:]
        var names: [Int32: String] = [:]
        var pid: Int32 = 0
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": names[pid] = String(value)
            case "n":
                // "*:3000", "127.0.0.1:5173", "[::1]:5173"
                if let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) {
                    ports[pid, default: []].insert(port)
                    addrs[pid, default: []].insert(String(value[..<colon]))
                }
            default: break
            }
        }

        return ports.map { pid, set in
            let exe = executablePath(pid)
            let argv = arguments(pid)
            let cwd = workingDirectory(pid)
            let root = cwd.flatMap(findGitRoot)
            return PortProcess(
                pid: pid,
                ports: set.sorted(),
                name: exe.map { ($0 as NSString).lastPathComponent } ?? names[pid] ?? "?",
                command: shorten(argv.isEmpty ? [names[pid] ?? "?"] : argv),
                executable: exe,
                cwd: cwd,
                startDate: startDate(pid),
                isSystem: isSystemProcess(exe),
                addresses: addrs[pid] ?? [],
                source: findSource(argv, cwd: cwd),
                projectRoot: root,
                gitBranch: root.flatMap(gitBranch)
            )
        }
        .sorted { ($0.isDevServer ? 0 : 1, $0.ports.first ?? 0) < ($1.isDevServer ? 0 : 1, $1.ports.first ?? 0) }
    }

    // MARK: 위치

    /// 명령줄에서 소스를 찾는다: 실제로 있는 스크립트 파일(node_modules 안의 도구 제외) 또는 `-m 모듈`.
    static func findSource(_ argv: [String], cwd: String?) -> PortProcess.Source? {
        let exts: Set<String> = ["js", "mjs", "cjs", "ts", "mts", "tsx", "py", "rb", "php", "go", "sh", "pl", "lua", "jar"]
        var i = 1
        while i < argv.count {
            let a = argv[i]
            if a == "-m", i + 1 < argv.count { return .module(argv[i + 1]) }
            if !a.hasPrefix("-") {
                let path = a.hasPrefix("/") ? a : cwd.map { ($0 as NSString).appendingPathComponent(a) } ?? a
                let std = (path as NSString).standardizingPath
                var isDir: ObjCBool = false
                if exts.contains((std as NSString).pathExtension.lowercased()), !std.contains("/node_modules/") {
                    if FileManager.default.fileExists(atPath: std, isDirectory: &isDir) {
                        if !isDir.boolValue { return .file(std) }
                    } else {
                        return .missing(std)
                    }
                }
            }
            i += 1
        }
        return nil
    }

    /// 홈 폴더 안에서만 찾는다 (/opt/homebrew 같은 도구 저장소를 프로젝트로 오해하지 않도록).
    static func findGitRoot(_ start: String) -> String? {
        var dir = start
        let home = NSHomeDirectory()
        guard dir.hasPrefix(home + "/") else { return nil }
        while dir != "/" && dir.count > 1 {
            if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(".git")) { return dir }
            if dir == home { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// .git/HEAD를 읽어 브랜치 이름. worktree(.git 파일)는 gitdir을 따라간다.
    static func gitBranch(_ root: String) -> String? {
        var gitDir = (root as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDir, isDirectory: &isDir) else { return nil }
        if !isDir.boolValue,
           let text = try? String(contentsOfFile: gitDir, encoding: .utf8),
           let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
            let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = path.hasPrefix("/") ? path : (root as NSString).appendingPathComponent(path)
        }
        guard let head = try? String(contentsOfFile: (gitDir as NSString).appendingPathComponent("HEAD"), encoding: .utf8)
        else { return nil }
        let h = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("ref: refs/heads/") { return String(h.dropFirst("ref: refs/heads/".count)) }
        return String(h.prefix(7))   // detached HEAD
    }

    static func tilde(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// 화면에 보일 경로: 홈은 `~`, 임시 폴더는 `$TMPDIR`.
    static func displayPath(_ path: String) -> String {
        let tmp = (NSTemporaryDirectory() as NSString).standardizingPath
        let std = (path as NSString).standardizingPath
        if std == tmp { return "$TMPDIR" }
        if std.hasPrefix(tmp + "/") { return "$TMPDIR" + std.dropFirst(tmp.count) }
        return tilde(path)
    }

    static func isLoopback(_ a: String) -> Bool {
        a.hasPrefix("127.") || a == "[::1]" || a == "localhost" || a == "[::ffff:127.0.0.1]"
    }

    /// 개발 서버가 아닌 것: macOS 구성 요소와 .app 번들 안의 앱(AirPlay, Spotify 등).
    static func isSystemProcess(_ exe: String?) -> Bool {
        guard let exe else { return true }
        let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/"]
        if systemPrefixes.contains(where: exe.hasPrefix) { return true }
        // Python.framework의 Python.app은 앱이 아니라 python 실행 파일이다 (uvicorn, http.server 등).
        if exe.hasSuffix("/Python.app/Contents/MacOS/Python") { return false }
        if exe.contains("/Contents/MacOS/") { return true }   // .app 번들(복제본 .app.bundle 포함)
        return false
    }

    // MARK: 프로세스 정보

    static func executablePath(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    static func startDate(_ pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
    }

    /// sysctl KERN_PROCARGS2: [argc][실행 경로\0 …\0][argv[0]\0 argv[1]\0 …]
    static func arguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }
        let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }     // 실행 경로 건너뛰기
        while i < size && buf[i] == 0 { i += 1 }     // 패딩
        var args: [String] = []
        while i < size && args.count < Int(argc) {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    /// 경로 인자는 파일 이름만 남긴다: `/opt/.../bin/node /x/.bin/vite --port 5175` → `node vite --port 5175`.
    /// `--opt=/a/b/c` 같은 값도 마지막 이름만.
    static func shorten(_ argv: [String]) -> String {
        argv.prefix(10).map { arg -> String in
            if let eq = arg.firstIndex(of: "="), arg[arg.index(after: eq)...].hasPrefix("/") {
                let value = String(arg[arg.index(after: eq)...])
                return arg[...eq] + (value as NSString).lastPathComponent
            }
            if arg.hasPrefix("/") || arg.hasPrefix("./") || arg.hasPrefix("~/") {
                return (arg as NSString).lastPathComponent
            }
            return arg
        }.joined(separator: " ")
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
