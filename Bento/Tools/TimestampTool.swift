import SwiftUI

struct TimestampTool: ToolView {
    static let meta = ToolMeta(
        id: "timestamp", name: "时间戳转换", category: .encoding, layout: .form,
        symbol: "clock",
        aliases: ["ts", "time", "timestamp", "sjc", "shijianchuo", "unix"]
    )

    @State private var input = "\(Int(Date().timeIntervalSince1970))"
    @State private var zoneID = TimeZone.current.identifier
    @State private var tick = Date()

    /// 常用时区，够日常排查了；全量列表塞进 Picker 反而难选
    private static let zones = [
        TimeZone.current.identifier, "UTC", "Asia/Shanghai", "Asia/Tokyo",
        "Europe/London", "America/New_York", "America/Los_Angeles",
    ].reduced()

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "时区")
            Picker("", selection: $zoneID) {
                ForEach(Self.zones, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 190)
            Spacer()
            Button("现在") { input = "\(Int(Date().timeIntervalSince1970))" }
                .bentoButton(prominent: true)
            Button("毫秒") { input = "\(Int(Date().timeIntervalSince1970 * 1000))" }
                .bentoButton()
        } content: {
            Card {
                HStack(spacing: 14) {
                    TextField("", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .sunkenSurface(radius: 8)

                    Text(unitLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 128, alignment: .leading)

                    Button("−1 天") { shift(-86400) }.bentoButton(plain: true)
                    Button("+1 天") { shift(86400) }.bentoButton(plain: true)
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "输出格式", dot: ToolCategory.encoding.tint, meta: "8 种 · 逐行复制") {
                ResultRows(rows: rows, keyWidth: 126)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - 解析

    /// 自动识别秒 / 毫秒 / 微秒：按位数判断，10 位是秒，13 位是毫秒
    private var date: Date? {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let n = Double(t) {
            switch t.replacingOccurrences(of: "-", with: "").count {
            case ...11:  return Date(timeIntervalSince1970: n)
            case 12...14: return Date(timeIntervalSince1970: n / 1000)
            default:      return Date(timeIntervalSince1970: n / 1_000_000)
            }
        }
        // 也接受日期字符串反查时间戳
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss",
                    "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.timeZone = zone
            if let d = df.date(from: t) { return d }
        }
        return nil
    }

    private var zone: TimeZone { TimeZone(identifier: zoneID) ?? .current }

    private var unitLabel: String {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard Double(t) != nil else { return t.isEmpty ? "" : "按日期字符串解析" }
        switch t.count {
        case ...11:   return "识别为秒"
        case 12...14: return "识别为毫秒"
        default:      return "识别为微秒"
        }
    }

    private var rows: [(String, String)] {
        guard let d = date else { return [] }
        func f(_ fmt: String, _ tz: TimeZone) -> String {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.timeZone = tz
            df.locale = Locale(identifier: "en_US_POSIX")
            return df.string(from: d)
        }
        let week = DateFormatter()
        week.locale = Locale(identifier: "zh_Hans")
        week.timeZone = zone
        week.dateFormat = "EEEE"

        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "zh_Hans")

        let iso = ISO8601DateFormatter()
        iso.timeZone = zone
        iso.formatOptions = [.withInternetDateTime]

        return [
            ("本地时间", "\(f("yyyy-MM-dd HH:mm:ss", zone))  \(week.string(from: d))"),
            ("UTC", f("yyyy-MM-dd HH:mm:ss", TimeZone(identifier: "UTC")!)),
            ("ISO 8601", iso.string(from: d)),
            ("RFC 2822", f("EEE, dd MMM yyyy HH:mm:ss Z", zone)),
            ("相对时间", rel.localizedString(for: d, relativeTo: tick)),
            ("秒", "\(Int(d.timeIntervalSince1970))"),
            ("毫秒", "\(Int(d.timeIntervalSince1970 * 1000))"),
            ("Apple 纪元", "\(Int(d.timeIntervalSinceReferenceDate))  // 2001-01-01 起"),
        ]
    }

    private func shift(_ seconds: Double) {
        guard let d = date else { return }
        let isMillis = input.trimmingCharacters(in: .whitespaces).count >= 12
        let v = d.addingTimeInterval(seconds).timeIntervalSince1970
        input = "\(Int(isMillis ? v * 1000 : v))"
    }

    private var status: StatusLine {
        if input.trimmingCharacters(in: .whitespaces).isEmpty {
            return StatusLine(level: .idle, text: "等待输入 · 点「现在」填入当前时间",
                              trailing: zoneID, trailingKey: "⌄")
        }
        guard date != nil else {
            return StatusLine(level: .error, text: "无法解析为时间戳或日期",
                              trailing: zoneID, trailingKey: "⌄")
        }
        return StatusLine(level: .ok, text: "已解析 · \(unitLabel)",
                          trailing: zoneID, trailingKey: "⌄")
    }
}

private extension Array where Element == String {
    /// 当前时区可能已经在列表里，去重后保持顺序
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
