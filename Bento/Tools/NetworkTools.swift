import SwiftUI
import Darwin

// MARK: - IP 信息

struct IPInfoTool: ToolView {
    static let meta = ToolMeta(
        id: "ipinfo", name: "IP 信息", category: .network, layout: .form,
        symbol: "wifi",
        aliases: ["ip", "network", "interface", "wl", "wangluo"]
    )

    @State private var publicIP: String?
    @State private var fetching = false
    @State private var error: String?

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "本机接口")
            Text("从 getifaddrs 直接读，不发任何请求")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            Button(fetching ? "查询中…" : (publicIP == nil ? "查外网 IP" : "重新查询")) {
                fetchPublic()
            }
            .bentoButton(prominent: publicIP == nil)
            .disabled(fetching)
        } content: {
            Card(title: "外网 IP", dot: ToolCategory.network.tint,
                 meta: publicIP == nil ? "未查询" : "ipify.org") {
                HStack(spacing: 14) {
                    Text(publicIP ?? "—")
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                    if let ip = publicIP { CopyButton(value: ip) }
                    Spacer()
                    Text(publicIP == nil
                         ? "查询会向 api.ipify.org 发一次请求 —— 点了才发"
                         : (error ?? "已获取"))
                        .font(Tokens.small)
                        .foregroundStyle(styleIf(error == nil, .tertiary, Tokens.error))
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "网络接口", dot: ToolCategory.image.tint,
                 meta: "\(interfaces.count) 个活跃") {
                ResultRows(rows: interfaces, keyWidth: 132)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// getifaddrs 直接枚举，不依赖任何外部服务
    private var interfaces: [(String, String)] {
        var out: [(String, String)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0,
                  let addr = cur.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            var ip = String(cString: host)
            if let percent = ip.firstIndex(of: "%") { ip = String(ip[..<percent]) }  // 去掉 %en0 作用域

            let name = String(cString: cur.pointee.ifa_name)
            let kind = family == UInt8(AF_INET) ? "IPv4" : "IPv6"
            let label = "\(name)  \(kind)"
            let note = Self.describe(interface: name)
            out.append((label, note.isEmpty ? ip : "\(ip)    \(note)"))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    private static func describe(interface name: String) -> String {
        if name.hasPrefix("en0") { return "// 通常是 Wi-Fi / 有线" }
        if name.hasPrefix("en") { return "// 以太网 / Thunderbolt" }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") { return "// VPN 隧道" }
        if name.hasPrefix("bridge") { return "// 网桥（虚拟机 / 共享网络）" }
        if name.hasPrefix("awdl") { return "// AirDrop / 隔空播放" }
        if name.hasPrefix("llw") { return "// 低延迟 Wi-Fi" }
        return ""
    }

    private func fetchPublic() {
        fetching = true
        error = nil
        Task {
            let r = await HTTPClient.send(HTTPClient.Request(url: "https://api.ipify.org"))
            await MainActor.run {
                if let e = r.error { error = e } else { publicIP = r.bodyText.trimmed }
                fetching = false
            }
        }
    }

    private var status: StatusLine {
        let v4 = interfaces.filter { $0.0.contains("IPv4") }.count
        return StatusLine(level: .ok,
                          text: "\(interfaces.count) 个活跃接口（\(v4) 个 IPv4）· 已排除回环",
                          trailing: "getifaddrs", trailingKey: "⌄")
    }
}

// MARK: - DNS / Ping

struct DNSTool: ToolView {
    static let meta = ToolMeta(
        id: "dns", name: "DNS / Ping", category: .network, layout: .stacked,
        symbol: "point.3.connected.trianglepath.dotted",
        aliases: ["dns", "dig", "ping", "nslookup", "jx", "jiexi"]
    )

    private static let types = ["A", "AAAA", "CNAME", "MX", "TXT", "NS", "SOA"]

    @State private var host = "example.com"
    @State private var recordType = "A"
    @State private var server = ""
    @State private var digOutput = ""
    @State private var pingOutput = ""
    @State private var running = false

    init() {}

    var body: some View {
        StackLayout(status: status) {
            TextField("域名或 IP", text: $host)
                .textFieldStyle(.plain).font(Tokens.mono)
                .padding(.horizontal, 10).frame(width: 200, height: 28)
                .sunkenSurface(radius: 7)
                .onSubmit { runDig() }
            BentoSegments(options: Self.types.map { ($0, $0) }, selection: $recordType)
            TextField("@DNS 服务器（可空）", text: $server)
                .textFieldStyle(.plain).font(Tokens.mono)
                .padding(.horizontal, 10).frame(width: 140, height: 28)
                .sunkenSurface(radius: 7)
            Spacer()
            Button("查询") { runDig() }.bentoButton(prominent: true).disabled(running)
            Button("Ping ×4") { runPing() }.bentoButton().disabled(running)
        } content: {
            HStack(alignment: .top, spacing: Tokens.gapCard) {
                Card(title: "dig", dot: ToolCategory.network.tint, meta: digMeta) {
                    CodeArea(text: .constant(digOutput), isEditable: false,
                             placeholder: "点「查询」")
                }
                Card(title: "ping", dot: ToolCategory.style.tint, meta: pingMeta) {
                    CodeArea(text: .constant(pingOutput), isEditable: false,
                             placeholder: "点「Ping ×4」（最多等 8 秒）")
                }
            }

            Card(title: "常用 DNS", dot: ToolCategory.image.tint, meta: "点一下填入") {
                HStack(spacing: 6) {
                    ForEach([("系统默认", ""), ("Cloudflare", "1.1.1.1"), ("Google", "8.8.8.8"),
                             ("阿里", "223.5.5.5"), ("腾讯", "119.29.29.29")], id: \.0) { name, ip in
                        Button(name) { server = ip; runDig() }
                            .bentoButton(prominent: server == ip && !ip.isEmpty)
                    }
                    Spacer()
                    Text("换服务器查同一域名，可以看出是不是被 DNS 污染 / 缓存不一致")
                        .font(Tokens.small).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Tokens.padCard)
                .padding(.bottom, Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var digMeta: String {
        digOutput.isEmpty ? "—" : "\(recordType) 记录"
    }
    private var pingMeta: String {
        pingOutput.isEmpty ? "—" : (pingOutput.contains("0.0% packet loss") ? "全部到达" : "有丢包")
    }

    private func runDig() {
        guard ShellRunner.isValidHost(host) else { digOutput = "主机名不合法"; return }
        running = true
        var args = ["+noall", "+answer", "+stats", host, recordType]
        if !server.trimmed.isEmpty, ShellRunner.isValidHost(server) {
            args.insert("@\(server.trimmed)", at: 0)
        }
        Task {
            let out = await ShellRunner.runAsync(.dig, args, timeout: 8)
            await MainActor.run {
                digOutput = out.timedOut ? "查询超时（8s）" : out.text
                running = false
            }
        }
    }

    private func runPing() {
        guard ShellRunner.isValidHost(host) else { pingOutput = "主机名不合法"; return }
        running = true
        Task {
            // -c 4 限制次数、-t 6 限制总时长，再叠 ShellRunner 的 8s 硬超时
            let out = await ShellRunner.runAsync(.ping, ["-c", "4", "-t", "6", host], timeout: 8)
            await MainActor.run {
                pingOutput = out.timedOut ? "超时 —— 目标可能不响应 ICMP" : out.text
                running = false
            }
        }
    }

    private var status: StatusLine {
        if running {
            return StatusLine(level: .warning, text: "执行中…", trailing: "dig / ping", trailingKey: "⌄")
        }
        if digOutput.isEmpty && pingOutput.isEmpty {
            return StatusLine(level: .idle,
                              text: "直接调系统的 dig / ping —— 非沙盒才能这么干",
                              trailing: "dig / ping", trailingKey: "⌄")
        }
        if digOutput.contains("NXDOMAIN") {
            return StatusLine(level: .error, text: "NXDOMAIN —— 域名不存在",
                              trailing: "dig / ping", trailingKey: "⌄")
        }
        if let line = digOutput.components(separatedBy: .newlines)
            .first(where: { $0.contains("Query time") }) {
            return StatusLine(level: .ok, text: line.trimmed, trailing: "dig / ping", trailingKey: "⌄")
        }
        return StatusLine(level: .ok, text: "已完成", trailing: "dig / ping", trailingKey: "⌄")
    }
}

// MARK: - 证书检查

struct CertTool: ToolView {
    static let meta = ToolMeta(
        id: "cert", name: "证书检查", category: .network, layout: .form,
        symbol: "lock.shield",
        aliases: ["cert", "tls", "ssl", "x509", "zs", "zhengshu"]
    )

    struct Info {
        var subject = ""
        var issuer = ""
        var notBefore = ""
        var notAfter = ""
        var daysLeft: Int?
        var san: [String] = []
        var signatureAlgorithm = ""
        var keyInfo = ""
        var serial = ""
        var chainDepth = 0
        var protocolVersion = ""
        var cipher = ""
    }

    @State private var host = "example.com"
    @State private var port = "443"
    @State private var info: Info?
    @State private var raw = ""
    @State private var running = false
    @State private var error: String?

    init() {}

    var body: some View {
        StackLayout(status: status) {
            TextField("域名", text: $host)
                .textFieldStyle(.plain).font(Tokens.mono)
                .padding(.horizontal, 10).frame(width: 220, height: 28)
                .sunkenSurface(radius: 7)
                .onSubmit { check() }
            Text(":").foregroundStyle(.tertiary)
            TextField("443", text: $port)
                .textFieldStyle(.plain).font(Tokens.mono)
                .padding(.horizontal, 10).frame(width: 60, height: 28)
                .sunkenSurface(radius: 7)
            Spacer()
            Button(running ? "连接中…" : "检查") { check() }
                .bentoButton(prominent: true).disabled(running)
        } content: {
            if let i = info {
                Card(title: "有效期", dot: expiryColor(i), meta: expiryMeta(i)) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(i.daysLeft.map { "\($0) 天" } ?? "—")
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                            Text("剩余").font(Tokens.small).foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("生效  \(i.notBefore)").font(Tokens.mono)
                            Text("到期  \(i.notAfter)").font(Tokens.mono)
                        }
                        Spacer()
                    }
                    .padding(Tokens.padCard)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "证书", dot: ToolCategory.network.tint, meta: "\(i.chainDepth) 级链") {
                    ResultRows(rows: certRows(i), keyWidth: 118)
                }
                .fixedSize(horizontal: false, vertical: true)

                Card(title: "SAN（\(i.san.count) 个域名）", dot: ToolCategory.image.tint,
                     meta: matchesHost(i) ? "包含 \(host)" : "⚠︎ 不包含 \(host)") {
                    ResultRows(rows: i.san.enumerated().map { ("#\($0.offset + 1)", $0.element) },
                               keyWidth: 50)
                        .frame(maxHeight: .infinity)
                }
            } else {
                Card {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(error ?? "输入域名后点「检查」")
                            .font(Tokens.body)
                            .foregroundStyle(styleIf(error == nil, .secondary, Tokens.error))
                        Text("走 openssl s_client，能看到完整链、SAN 和协商出的 TLS 版本")
                            .font(Tokens.small).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
    }

    private func certRows(_ i: Info) -> [(String, String)] {
        [
            ("主体", i.subject),
            ("颁发者", i.issuer),
            ("签名算法", i.signatureAlgorithm),
            ("公钥", i.keyInfo),
            ("序列号", i.serial),
            ("TLS", "\(i.protocolVersion)  \(i.cipher)"),
        ].filter { !$0.1.trimmed.isEmpty }
    }

    private func matchesHost(_ i: Info) -> Bool {
        let h = host.lowercased()
        return i.san.contains { san in
            let s = san.lowercased()
            if s == h { return true }
            if s.hasPrefix("*.") {
                let suffix = String(s.dropFirst(1))       // ".example.com"
                return h.hasSuffix(suffix) && h.dropLast(suffix.count).contains(".") == false
            }
            return false
        }
    }

    private func expiryColor(_ i: Info) -> Color {
        guard let d = i.daysLeft else { return Tokens.tertiaryLabel }
        return d < 0 ? Tokens.error : (d < 30 ? Tokens.warning : Tokens.ok)
    }

    private func expiryMeta(_ i: Info) -> String {
        guard let d = i.daysLeft else { return "—" }
        if d < 0 { return "已过期 \(-d) 天" }
        if d < 30 { return "即将过期" }
        return "正常"
    }

    private func check() {
        guard ShellRunner.isValidHost(host), let p = Int(port), p > 0, p < 65536 else {
            error = "域名或端口不合法"
            return
        }
        running = true
        error = nil
        info = nil
        let target = "\(host.trimmed):\(p)"
        let serverName = host.trimmed

        Task {
            // -servername 走 SNI，否则共享 IP 的站点会给错证书
            let out = await ShellRunner.runAsync(
                .openssl,
                ["s_client", "-connect", target, "-servername", serverName, "-showcerts"],
                stdin: "", timeout: 12)

            guard out.succeeded || out.stdout.contains("BEGIN CERTIFICATE") else {
                await MainActor.run {
                    error = out.timedOut ? "连接超时（12s）"
                        : (out.stderr.components(separatedBy: .newlines).first { !$0.isEmpty }
                           ?? "连接失败")
                    running = false
                }
                return
            }

            // 再用 x509 把首张证书解成文本
            let pem = Self.firstPEM(from: out.stdout)
            let detail = pem.isEmpty ? ShellRunner.Output()
                : await ShellRunner.runAsync(.openssl,
                    ["x509", "-noout", "-subject", "-issuer", "-dates", "-serial",
                     "-ext", "subjectAltName", "-text"],
                    stdin: pem, timeout: 8)

            let parsed = Self.parse(handshake: out.stdout, cert: detail.stdout)
            await MainActor.run {
                raw = out.stdout
                info = parsed
                running = false
            }
        }
    }

    private static func firstPEM(from text: String) -> String {
        guard let start = text.range(of: "-----BEGIN CERTIFICATE-----"),
              let end = text.range(of: "-----END CERTIFICATE-----",
                                   range: start.upperBound..<text.endIndex)
        else { return "" }
        return String(text[start.lowerBound..<end.upperBound]) + "\n"
    }

    private static func parse(handshake: String, cert: String) -> Info {
        var i = Info()

        func value(_ prefix: String, in text: String) -> String? {
            text.components(separatedBy: .newlines)
                .first { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        }

        i.subject = value("subject=", in: cert) ?? ""
        i.issuer = value("issuer=", in: cert) ?? ""
        i.serial = value("serial=", in: cert) ?? ""

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        func date(_ raw: String?) -> (String, Date?) {
            guard let raw else { return ("", nil) }
            let cleaned = raw.replacingOccurrences(of: "  ", with: " ")
            guard let d = df.date(from: cleaned) else { return (raw, nil) }
            let out = DateFormatter()
            out.dateFormat = "yyyy-MM-dd HH:mm"
            return (out.string(from: d), d)
        }
        let (beforeText, _) = date(value("notBefore=", in: cert))
        let (afterText, afterDate) = date(value("notAfter=", in: cert))
        i.notBefore = beforeText
        i.notAfter = afterText
        if let afterDate {
            i.daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: afterDate).day
        }

        // SAN 在 -ext 输出里是「X509v3 Subject Alternative Name:」下一行
        let lines = cert.components(separatedBy: .newlines)
        if let idx = lines.firstIndex(where: { $0.contains("Subject Alternative Name") }),
           idx + 1 < lines.count {
            i.san = lines[idx + 1]
                .components(separatedBy: ",")
                .map { $0.replacingOccurrences(of: "DNS:", with: "")
                         .trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let algo = lines.first(where: { $0.contains("Signature Algorithm:") }) {
            i.signatureAlgorithm = algo.components(separatedBy: ":").last?.trimmed ?? ""
        }
        if let key = lines.first(where: { $0.contains("Public-Key:") }) {
            i.keyInfo = key.trimmed
        }

        // 握手信息在 s_client 的输出里
        let hs = handshake.components(separatedBy: .newlines)
        if let proto = hs.first(where: { $0.contains("Protocol  :") || $0.contains("Protocol:") }) {
            i.protocolVersion = proto.components(separatedBy: ":").last?.trimmed ?? ""
        }
        if let cipher = hs.first(where: { $0.contains("Cipher    :") || $0.contains("Cipher:") }) {
            i.cipher = cipher.components(separatedBy: ":").last?.trimmed ?? ""
        }
        i.chainDepth = handshake.components(separatedBy: "-----BEGIN CERTIFICATE-----").count - 1
        return i
    }

    private var status: StatusLine {
        if running {
            return StatusLine(level: .warning, text: "openssl s_client 连接中…",
                              trailing: "openssl", trailingKey: "⌄")
        }
        if let e = error {
            return StatusLine(level: .error, text: e, trailing: "openssl", trailingKey: "⌄")
        }
        guard let i = info else {
            return StatusLine(level: .idle, text: "输入域名后检查",
                              trailing: "openssl", trailingKey: "⌄")
        }
        guard let d = i.daysLeft else {
            return StatusLine(level: .warning, text: "拿到证书但日期解析失败",
                              trailing: "openssl", trailingKey: "⌄")
        }
        if d < 0 {
            return StatusLine(level: .error, text: "证书已过期 \(-d) 天",
                              trailing: "openssl", trailingKey: "⌄")
        }
        if !matchesHost(i) {
            return StatusLine(level: .error,
                              text: "SAN 里不包含 \(host) —— 浏览器会报证书名称不匹配",
                              trailing: "openssl", trailingKey: "⌄")
        }
        return StatusLine(level: d < 30 ? .warning : .ok,
                          text: "剩余 \(d) 天 · \(i.protocolVersion) · \(i.chainDepth) 级链 · SAN 匹配",
                          trailing: "openssl", trailingKey: "⌄")
    }
}

// MARK: - WebSocket

struct WebSocketTool: ToolView {
    static let meta = ToolMeta(
        id: "websocket", name: "WebSocket", category: .network, layout: .stacked,
        symbol: "arrow.up.arrow.down.circle",
        aliases: ["websocket", "ws", "socket", "tcxx"]
    )

    @State private var client = WSClient()
    @State private var url = "wss://echo.websocket.org"
    @State private var message = "hello"

    init() {}

    var body: some View {
        StackLayout(status: status) {
            TextField("wss://…", text: $url)
                .textFieldStyle(.plain).font(Tokens.mono)
                .padding(.horizontal, 10).frame(width: 300, height: 28)
                .sunkenSurface(radius: 7)
                .disabled(client.state != .idle)
            Spacer()
            if client.state == .connected {
                Button("断开") { client.disconnect() }.bentoButton()
            } else {
                Button(client.state == .connecting ? "连接中…" : "连接") { client.connect(url) }
                    .bentoButton(prominent: true)
                    .disabled(client.state == .connecting)
            }
            Button("清空日志") { client.log.removeAll() }.bentoButton(plain: true)
        } content: {
            Card(title: "消息", dot: ToolCategory.network.tint, meta: "\(client.log.count) 条") {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(client.log) { entry in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(entry.direction.symbol)
                                        .foregroundStyle(entry.direction.color)
                                        .frame(width: 18)
                                    Text(entry.time)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 62, alignment: .leading)
                                    Text(entry.text)
                                        .font(Tokens.mono)
                                        .foregroundStyle(styleIf(entry.direction == .error, Tokens.error, .primary))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, Tokens.padCard)
                                .padding(.vertical, 3)
                                .id(entry.id)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .onChange(of: client.log.count) { _, _ in
                        if let last = client.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Card(title: "发送", dot: ToolCategory.encoding.tint,
                 meta: client.state == .connected ? "已连接" : "未连接") {
                HStack(spacing: 10) {
                    TextField("要发送的文本…", text: $message)
                        .textFieldStyle(.plain).font(Tokens.mono)
                        .padding(.horizontal, 10).frame(height: 30)
                        .sunkenSurface(radius: 7)
                        .onSubmit { client.send(message) }
                    Button("发送") { client.send(message) }
                        .bentoButton(prominent: true)
                        .disabled(client.state != .connected || message.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    Button("Ping") { client.ping() }
                        .bentoButton()
                        .disabled(client.state != .connected)
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear { client.disconnect() }
    }

    private var status: StatusLine {
        switch client.state {
        case .idle:
            return StatusLine(level: .idle, text: "未连接 · URLSessionWebSocketTask",
                              trailing: "WebSocket", trailingKey: "⌄")
        case .connecting:
            return StatusLine(level: .warning, text: "连接中…", trailing: "WebSocket", trailingKey: "⌄")
        case .connected:
            return StatusLine(level: .ok,
                              text: "已连接 · 收 \(client.received) 发 \(client.sent)",
                              trailing: "WebSocket", trailingKey: "⌄")
        case .failed:
            return StatusLine(level: .error, text: client.lastError ?? "连接失败",
                              trailing: "WebSocket", trailingKey: "⌄")
        }
    }
}

/// WebSocket 连接管理。URLSessionWebSocketTask 的 receive 是一次性的，
/// 收到一条之后必须再调一次才能收下一条 —— 这里用递归续上。
@Observable
final class WSClient {
    enum State { case idle, connecting, connected, failed }

    struct Entry: Identifiable {
        enum Direction {
            case sent, received, system, error
            var symbol: String {
                switch self {
                case .sent: return "↑"
                case .received: return "↓"
                case .system: return "·"
                case .error: return "✕"
                }
            }
            var color: Color {
                switch self {
                case .sent: return Tokens.accent
                case .received: return Tokens.ok
                case .system: return Tokens.tertiaryLabel
                case .error: return Tokens.error
                }
            }
        }
        let id = UUID()
        let direction: Direction
        let text: String
        let time: String
    }

    private(set) var state: State = .idle
    private(set) var lastError: String?
    private(set) var sent = 0
    private(set) var received = 0
    var log: [Entry] = []

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    func connect(_ urlString: String) {
        guard let url = URL(string: urlString.trimmed),
              ["ws", "wss"].contains(url.scheme?.lowercased() ?? "") else {
            append(.error, "URL 无效 —— 需要 ws:// 或 wss://")
            state = .failed
            return
        }
        disconnect()
        state = .connecting
        lastError = nil

        let s = URLSession(configuration: .ephemeral)
        session = s
        let t = s.webSocketTask(with: url)
        task = t
        t.resume()
        append(.system, "正在连接 \(url.absoluteString)")
        listen()
        // 用一次 ping 确认握手真的成功了 —— resume() 本身不代表连上
        t.sendPing { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.state = .failed
                    self.lastError = error.localizedDescription
                    self.append(.error, error.localizedDescription)
                } else {
                    self.state = .connected
                    self.append(.system, "已连接")
                }
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if state != .idle { append(.system, "已断开") }
        state = .idle
    }

    func send(_ text: String) {
        guard let task, state == .connected else { return }
        task.send(.string(text)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.append(.error, "发送失败：\(error.localizedDescription)")
                } else {
                    self.sent += 1
                    self.append(.sent, text)
                }
            }
        }
    }

    func ping() {
        task?.sendPing { [weak self] error in
            DispatchQueue.main.async {
                self?.append(error == nil ? .system : .error,
                             error == nil ? "pong" : "ping 失败：\(error!.localizedDescription)")
            }
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.received += 1
                    switch message {
                    case .string(let s): self.append(.received, s)
                    case .data(let d): self.append(.received, "<\(d.count) 字节二进制>")
                    @unknown default: self.append(.received, "<未知类型>")
                    }
                    self.listen()      // 续上，否则只能收一条
                case .failure(let error):
                    if self.state != .idle {
                        self.state = .failed
                        self.lastError = error.localizedDescription
                        self.append(.error, error.localizedDescription)
                    }
                }
            }
        }
    }

    private func append(_ direction: Entry.Direction, _ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SS"
        log.append(Entry(direction: direction, text: text, time: f.string(from: Date())))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}
