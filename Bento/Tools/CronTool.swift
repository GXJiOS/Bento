import SwiftUI

struct CronTool: ToolView {
    static let meta = ToolMeta(
        id: "cron", name: "Cron 解析", category: .formatting, layout: .form,
        symbol: "calendar.badge.clock",
        aliases: ["cron", "crontab", "schedule", "dsrw", "dingshi"]
    )

    private static let presets: [(String, String)] = [
        ("每分钟", "* * * * *"),
        ("每小时", "0 * * * *"),
        ("每天零点", "0 0 * * *"),
        ("工作日 9:30", "30 9 * * 1-5"),
        ("每 15 分钟", "*/15 * * * *"),
        ("每月 1 号", "0 0 1 * *"),
    ]

    @State private var expr = "30 9 * * 1-5"

    init() {}

    var body: some View {
        StackLayout(status: status) {
            OptionLabel(text: "预设")
            ForEach(Self.presets, id: \.0) { name, e in
                Button(name) { expr = e }.bentoButton()
            }
            Spacer()
        } content: {
            Card {
                HStack(spacing: 14) {
                    TextField("* * * * *", text: $expr)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .sunkenSurface(radius: 8)
                    Text(fieldLabels)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                }
                .padding(Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "人类可读", dot: ToolCategory.formatting.tint, meta: nil) {
                Text(cron?.humanReadable ?? "—")
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.padCard)
                    .padding(.bottom, Tokens.padCard)
            }
            .fixedSize(horizontal: false, vertical: true)

            Card(title: "未来 10 次执行", dot: ToolCategory.image.tint, meta: nextMeta) {
                ResultRows(rows: upcoming, keyWidth: 74)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: -

    private var parsed: Result<CronExpression, CronExpression.ParseError> {
        CronExpression.parse(expr)
    }

    private var cron: CronExpression? {
        if case .success(let c) = parsed { return c }
        return nil
    }

    private var fieldLabels: String {
        let n = expr.split(separator: " ").count
        return n == 6 ? "秒 分 时 日 月 周" : "分 时 日 月 周"
    }

    private var upcoming: [(String, String)] {
        guard let c = cron else { return [] }
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let wf = DateFormatter()
        wf.locale = Locale(identifier: "zh_Hans")
        wf.dateFormat = "EEE"
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "zh_Hans")

        return c.nextDates(after: now).enumerated().map { i, d in
            ("#\(i + 1)",
             "\(df.string(from: d))  \(wf.string(from: d))    \(rel.localizedString(for: d, relativeTo: now))")
        }
    }

    private var nextMeta: String {
        cron == nil ? "—" : "\(upcoming.count) 条 · 本地时区"
    }

    private var status: StatusLine {
        if expr.trimmed.isEmpty {
            return StatusLine(level: .idle, text: "等待输入", trailing: "Cron", trailingKey: "⌄")
        }
        switch parsed {
        case .failure(let err):
            return StatusLine(level: .error, text: err.localizedDescription,
                              trailing: "Cron", trailingKey: "⌄")
        case .success(let c):
            if upcoming.isEmpty {
                return StatusLine(level: .warning, text: "表达式有效，但未来 400 天内不会触发",
                                  trailing: "Cron", trailingKey: "⌄")
            }
            return StatusLine(level: .ok, text: c.humanReadable,
                              trailing: "Cron", trailingKey: "⌄")
        }
    }
}
