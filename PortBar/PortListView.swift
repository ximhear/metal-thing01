import SwiftUI

/// 글자 크기와 그에 맞춘 치수는 여기서만 정한다.
/// 단계: 0 = 처음 크기(작은 글자 10pt), 1 = 크게(기본), 2 = 더 크게.
/// `defaults write com.example.portbar textSize 2` 또는 실행 인자 `-textSize 2`로 바꾼다.
enum Typo {
    static let level: Int = {
        let d = UserDefaults.standard
        return d.object(forKey: "textSize") == nil ? 1 : min(max(d.integer(forKey: "textSize"), 0), 2)
    }()
    private static func pick(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat) -> CGFloat { [a, b, c][level] }

    static let header = Font.system(size: pick(13, 15, 16), weight: .semibold)
    static let port = Font.system(size: pick(13, 15, 16), weight: .semibold, design: .monospaced)
    static let title = Font.system(size: pick(13, 14, 15), weight: .medium)
    static let crumb = Font.system(size: pick(13, 14, 15))
    static let command = Font.system(size: pick(10, 12, 13), design: .monospaced)
    static let badge = Font.system(size: pick(10, 11, 12), weight: .medium)
    static let detail = Font.system(size: pick(10, 12, 13))     // 경로·소스, 그룹 머리줄, 버튼 글자
    static let small = Font.system(size: pick(10, 11, 12))      // 포트 아래 시간, 갱신 시각
    static let icon = Font.system(size: pick(13, 15, 16))

    static let popupWidth = pick(480, 520, 560)
    static let listHeight = pick(460, 500, 540)
    static let portColumn = pick(50, 58, 62)
    static let iconButton = CGSize(width: pick(26, 29, 31), height: pick(22, 24, 26))
    static let labelIcon = pick(14, 16, 17)
}

struct PortListView: View {
    @Environment(PortModel.self) private var model
    @State private var showSystem: Bool
    private let listHeight: CGFloat
    private let scrollToOthers: Bool
    private let demoConfirm: Bool

    /// 기본값이 실제 메뉴바 팝업. 나머지 인자는 스크린샷·디버깅 창에서만 쓴다.
    init(listHeight: CGFloat? = nil, expandOthers: Bool = false, demoConfirm: Bool = false) {
        self.listHeight = listHeight ?? Typo.listHeight
        self.scrollToOthers = expandOthers
        self.demoConfirm = demoConfirm
        _showSystem = State(initialValue: expandOthers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if model.devProcesses.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("실행 중인 개발 서버가 없어요")
                                    .font(Typo.title)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            let demoPid = demoConfirm ? model.devProcesses.dropFirst().first?.pid : nil
                            ForEach(model.devProcesses) { p in
                                ProcessRow(process: p, demoConfirm: p.pid == demoPid)
                            }
                        }

                        if !model.systemProcesses.isEmpty {
                            othersToggle.id("others")
                            if showSystem {
                                ForEach(model.systemProcesses) { ProcessRow(process: $0) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onAppear {
                    guard scrollToOthers else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { proxy.scrollTo("others", anchor: .top) }
                }
            }
            .frame(height: listHeight)   // 메뉴바 팝업에서는 높이를 정해 줘야 ScrollView가 0으로 줄지 않는다
            Divider()
            footer
        }
        .frame(width: Typo.popupWidth)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("개발 서버").font(Typo.header)
            Text(String(model.devProcesses.count))
                .font(Typo.header.monospacedDigit())
                .foregroundStyle(.secondary)
            if model.exposedCount > 0 {
                Badge(text: "외부 공개 \(model.exposedCount)", symbol: "globe", tint: .orange,
                      help: "같은 네트워크의 다른 기기에서도 접속할 수 있는 개발 서버 수")
            }
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").font(Typo.icon) }
                .buttonStyle(.borderless)
                .help("새로고침 (4초마다 자동)")
                .accessibilityLabel("새로고침")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 접어 둔 "개발 서버가 아닌 것" 그룹의 머리줄. 행과 같은 왼쪽 선에 맞춘다.
    private var othersToggle: some View {
        let others = model.systemProcesses
        return Button { showSystem.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(Typo.small.weight(.semibold))
                    .rotationEffect(.degrees(showSystem ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: showSystem)
                    .frame(width: 10)
                Text("개발 서버가 아닌 것 \(others.count)개")
                    .font(Typo.detail.weight(.medium))
                Text("macOS, 일반 앱, 임시 포트")
                    .font(Typo.detail)
                Spacer(minLength: 8)
                if !showSystem {
                    Text(portPreview(others))
                        .font(Typo.small.monospaced())
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .accessibilityLabel("개발 서버가 아닌 것 \(others.count)개")
        .accessibilityHint(showSystem ? "접기" : "펼치기")
    }

    /// 접혀 있을 때 안에 무엇이 있는지 짐작할 수 있게 잘 알려진 포트 몇 개를 보여 준다.
    private func portPreview(_ list: [PortProcess]) -> String {
        let ports = Set(list.flatMap(\.ports)).filter { $0 < 49152 }.sorted()
        let shown = ports.prefix(4).map { ":\($0)" }.joined(separator: " ")
        return ports.count > 4 ? shown + " …" : shown
    }

    private var footer: some View {
        HStack {
            if let t = model.lastScan {
                Text("갱신 \(t.formatted(date: .omitted, time: .standard))")
                    .font(Typo.small)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("PortBar 종료") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(Typo.detail)
                .keyboardShortcut("q")
                .help("PortBar를 끝내요 (⌘Q). 서버는 계속 실행돼요")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - 행

private struct ProcessRow: View {
    @Environment(PortModel.self) private var model
    let process: PortProcess
    @State private var hovering = false
    @State private var stopHover = false
    /// 종료는 두 단계: 첫 클릭은 [취소] [종료]만 보여 주고, 3초 안에 다시 눌러야 신호를 보낸다.
    @State private var confirming: Bool
    @State private var armed: Bool
    @State private var confirmToken = 0

    init(process: PortProcess, demoConfirm: Bool = false) {
        self.process = process
        _confirming = State(initialValue: demoConfirm)
        _armed = State(initialValue: demoConfirm)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                portColumn
                infoColumn
            }
            Spacer(minLength: 4)
            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
    }

    /// 포트 번호(최대 3개)와 그 아래 얼마나 오래 켜져 있었는지.
    private var portColumn: some View {
        let p = process
        let allPorts = p.ports.map { ":\($0)" }.joined(separator: " ")
        let started = p.startDate.map { " · \($0.formatted(date: .abbreviated, time: .shortened)) 시작" } ?? ""
        let pidHelp = "pid \(p.pid)\(started)"
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(p.ports.prefix(3), id: \.self) { port in
                Text(":\(String(port))")
                    .font(Typo.port)
                    .foregroundStyle(p.isDevServer ? .primary : .secondary)
                    .accessibilityLabel("포트 \(String(port))")
            }
            if p.ports.count > 3 {
                Text("+\(String(p.ports.count - 3))")
                    .font(Typo.small)
                    .foregroundStyle(.secondary)
                    .help(allPorts)
                    .accessibilityLabel("그 밖의 포트 \(String(p.ports.count - 3))개")
            }
            if let start = p.startDate {
                // 오래 켜 둔 서버는 같은 자리에서 노란 바탕으로 눈에 띄게 한다.
                let stale = p.isStale
                Text(uptimeShort(since: start))
                    .font(Typo.small.weight(stale ? .medium : .regular))
                    .foregroundStyle(stale ? .primary : .secondary)
                    .padding(.horizontal, stale ? 5 : 0)
                    .padding(.vertical, stale ? 1 : 0)
                    .background(stale ? Color.yellow.opacity(0.35) : Color.clear, in: Capsule())
                    .padding(.top, stale ? 1 : 0)
                    .help(stale ? "일주일 넘게 켜져 있어요. 아직 쓰는 서버인지 확인해 보세요\n" + pidHelp : pidHelp)
                    .accessibilityLabel(uptimeShort(since: start) + " 실행 중")
            }
        }
        .frame(width: Typo.portColumn, alignment: .leading)
        .help(pidHelp)
    }

    /// 무엇(프로젝트 · 하위 경로 · 명령) → 누가 접속할 수 있나(배지) → 어디서(경로).
    private var infoColumn: some View {
        let p = process
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(p.projectName ?? p.title)
                    .font(Typo.title)
                    .lineLimit(1)
                    .layoutPriority(2)
                if let crumb = p.projectCrumb {
                    Text(crumb)
                        .font(Typo.crumb)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .layoutPriority(1)
                }
                Text(p.command)
                    .font(Typo.command)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 80, alignment: .leading)
                    .help(p.command)
            }
            HStack(spacing: 4) {
                ExposureBadge(exposure: p.exposure)
                if let f = p.forwarder {
                    Badge(text: f, symbol: "arrow.left.arrow.right", tint: .purple,
                          help: "이 Mac에서 직접 실행한 서버가 아니라 다른 곳의 서버를 이 포트로 연결한 것")
                }
                if let b = p.gitBranch {
                    Badge(text: b, symbol: "arrow.triangle.branch", flexible: true, help: "git 브랜치: \(b)")
                }
            }
            LocationLine(process: p)
        }
    }

    @ViewBuilder private var actions: some View {
        let p = process
        if confirming {
            HStack(spacing: 6) {
                Button("취소") { cancelConfirm() }
                    .buttonStyle(PillButtonStyle())
                Button("종료") { cancelConfirm(); model.stop(p) }
                    .buttonStyle(PillButtonStyle(destructive: true))
                    .disabled(!armed)
                    .help("이 서버에 종료 신호(SIGTERM)를 보내요")
            }
        } else {
            HStack(spacing: 2) {
                if p.looksLikeWebServer {
                    iconButton("arrow.up.right.square", label: "브라우저에서 열기",
                               help: "브라우저에서 열기 (localhost:\(p.ports.first ?? 0))") { model.openInBrowser(p) }
                }
                Menu { menuItems } label: {
                    Image(systemName: "ellipsis").font(Typo.icon)
                        .frame(width: Typo.iconButton.width, height: Typo.iconButton.height)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .font(Typo.icon)          // 메뉴 버튼의 아이콘 크기는 라벨이 아니라 메뉴에 준 글자 크기를 따른다
                .imageScale(.large)
                .fixedSize()
                .opacity(0.6)   // 메뉴 버튼은 글자색으로 그려져 옆 아이콘보다 진하다. 같은 회색으로 맞춘다.
                .help("더 보기: 주소·경로·PID 복사, Finder에서 열기")
                .accessibilityLabel("더 보기")

                // 개발 서버만 여기서 끌 수 있다. 터미널·브라우저 같은 일반 앱은 실수로 꺼지지 않게 버튼을 두지 않는다.
                if p.isDevServer {
                    if model.stubborn.contains(p.pid) {
                        Button("강제 종료") { model.forceStop(p) }
                            .controlSize(.small)
                            .tint(.red)
                            .help("응답이 없어요. SIGKILL로 강제 종료")
                    } else if model.stopping.contains(p.pid) {
                        ProgressView().controlSize(.small).frame(width: Typo.iconButton.width)
                    } else {
                        iconButton("stop.circle", label: "이 서버 종료", help: "이 서버 종료 (SIGTERM)") { askStop() }
                            .foregroundStyle(stopHover ? Color.red : Color.secondary)
                            .onHover { stopHover = $0 }
                    }
                }
            }
        }
    }

    /// "…" 버튼과 우클릭이 같은 메뉴를 쓴다.
    @ViewBuilder private var menuItems: some View {
        let p = process
        if !p.isKnownNonHTTP {
            ForEach(p.ports.prefix(5), id: \.self) { port in
                Button("localhost:\(String(port)) 열기") { model.openInBrowser(p, port: port) }
            }
        }
        if let port = p.ports.first {
            Button("주소 복사 (localhost:\(String(port)))") { copy("http://localhost:\(port)") }
        }
        Divider()
        if let cwd = p.cwd {
            Button("실행 위치를 Finder에서 열기") { model.revealFolder(p) }
            Button("실행 위치 경로 복사") { copy(cwd) }
        }
        if case .file(let path)? = p.source {
            Button("소스 파일을 Finder에서 보기") { model.revealSource(path) }
            Button("소스 파일 경로 복사") { copy(path) }
        }
        if let root = p.projectRoot {
            Button("프로젝트 루트 경로 복사") { copy(root) }
        }
        Divider()
        Button("PID 복사 (\(String(p.pid)))") { copy(String(p.pid)) }
        Button("kill 명령 복사") { model.copyKillCommand(p) }
    }

    private func askStop() {
        confirming = true
        armed = false
        confirmToken += 1
        let token = confirmToken
        // 같은 자리를 연달아 눌러도 꺼지지 않게 0.3초 뒤부터 눌린다. 3초 동안 누르지 않으면 원래대로.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if token == confirmToken { armed = true } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if token == confirmToken { confirming = false } }
    }

    private func cancelConfirm() {
        confirming = false
        confirmToken += 1
    }

    private func iconButton(_ symbol: String, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(Typo.icon)
                .frame(width: Typo.iconButton.width, height: Typo.iconButton.height)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(label)
    }
}

/// 종료 확인 단계의 [취소] [종료]. 종료만 빨갛게 채운다.
private struct PillButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, destructive: destructive)
    }

    private struct Pill: View {
        let configuration: Configuration
        let destructive: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Typo.detail.weight(.medium))
                .foregroundStyle(destructive ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(destructive ? Color.red : Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.5))
                .contentShape(Rectangle())
        }
    }
}

func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - 위치

/// 실행 위치(작업 폴더)와 소스를 한 줄에. 누를 수 있는 것만 포인터를 올렸을 때 밑줄이 생긴다.
private struct LocationLine: View {
    @Environment(PortModel.self) private var model
    let process: PortProcess

    var body: some View {
        let p = process
        if p.hasInformativeFolder || p.source != nil {
            HStack(spacing: 10) {
                if p.hasInformativeFolder, let cwd = p.cwd {
                    LinkLabel(text: PortScanner.displayPath(cwd), symbol: "folder",
                              help: "실행 위치: \(cwd)\n누르면 Finder에서 열려요") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                    }
                }
                switch p.source {
                case .file(let path)?:
                    LinkLabel(text: relative(path, to: p.cwd), symbol: "doc.text",
                              help: "소스: \(path)\n누르면 Finder에서 보여 줘요") {
                        model.revealSource(path)
                    }
                case .module(let m)?:
                    Label("모듈 \(m)", systemImage: "shippingbox")
                        .labelStyle(TightLabelStyle())
                        .lineLimit(1)
                        .help("python -m \(m)")
                case .missing(let path)?:
                    Label {
                        Text("\(relative(path, to: p.cwd)) · 파일 없음")
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .labelStyle(TightLabelStyle())
                    .help("명령에 적힌 소스 파일이 지금 그 자리에 없어요: \(path)\n지워지거나 옮겨진 코드로 계속 돌고 있는 서버일 수 있어요")
                case nil:
                    EmptyView()
                }
            }
            .font(Typo.detail)
            .foregroundStyle(.secondary)
        }
    }

    private func relative(_ path: String, to base: String?) -> String {
        if let base, path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) }
        return PortScanner.displayPath(path)
    }
}

private struct LinkLabel: View {
    let text: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(text).underline(hovering).lineLimit(1).truncationMode(.head)
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(TightLabelStyle())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help(help)
    }
}

/// 아이콘 폭을 고정해 줄마다 글자가 같은 선에서 시작하게 한다.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.frame(width: Typo.labelIcon)
            configuration.title
        }
    }
}

// MARK: - 배지

private struct ExposureBadge: View {
    let exposure: PortProcess.Exposure
    var body: some View {
        switch exposure {
        case .loopback:
            Badge(text: "로컬 전용", symbol: "lock.fill",
                  help: "127.0.0.1 / ::1 에서만 대기 — 이 Mac에서만 접속할 수 있어요")
        case .network:
            Badge(text: "외부 공개", symbol: "globe", tint: .orange,
                  help: "모든 네트워크 주소(*, 0.0.0.0)에서 대기 — 같은 네트워크의 다른 기기도 접속할 수 있어요")
        case .specific(let ip):
            Badge(text: ip, symbol: "network", tint: .orange,
                  help: "\(ip) 주소에서 대기 — 그 네트워크의 다른 기기가 접속할 수 있어요")
        }
    }
}

/// `tint`가 없으면 눈에 덜 띄는 회색, 있으면 색 바탕 + 진한 글자(주의가 필요한 것만).
private struct Badge: View {
    let text: String
    let symbol: String
    var tint: Color? = nil
    var flexible = false      // 자리가 모자라면 가운데를 줄인다 (긴 브랜치 이름)
    let help: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(Typo.badge)
        .foregroundStyle(tint == nil ? .secondary : .primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.map { $0.opacity(0.22) } ?? Color.primary.opacity(0.07), in: Capsule())
        .fixedSize(horizontal: !flexible, vertical: true)
        .help(help)
        .accessibilityElement(children: .combine)
    }
}

/// "방금", "12분째", "3시간째", "27일째"
func uptimeShort(since date: Date) -> String {
    let s = Int(Date().timeIntervalSince(date))
    if s < 60 { return "방금" }
    if s < 3600 { return "\(s / 60)분째" }
    if s < 86400 { return "\(s / 3600)시간째" }
    return "\(s / 86400)일째"
}
