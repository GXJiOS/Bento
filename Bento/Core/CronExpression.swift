import Foundation

/// Cron 表达式解析。纯逻辑放 Core，UI 只负责显示 —— 这样能脱离 SwiftUI 直接跑测试。
struct CronExpression {
    var seconds: Set<Int>?      // 6 字段时才有
    var minutes: Set<Int>
    var hours: Set<Int>
    var days: Set<Int>
    var months: Set<Int>
    var weekdays: Set<Int>      // 0 = 周日（7 会被归一到 0）

    enum ParseError: LocalizedError, Equatable {
        case fieldCount(Int)
        /// 字段名随「有没有秒字段」变化，所以直接带上名字，不靠下标反查
        case badField(position: Int, name: String, text: String)

        var errorDescription: String? {
            switch self {
            case .fieldCount(let n):
                return "需要 5 个字段（分 时 日 月 周）或 6 个（含秒），当前 \(n) 个"
            case .badField(let pos, let name, let text):
                return "第 \(pos) 个字段「\(text)」无效（\(name)）"
            }
        }
    }

    static let monthNames = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                             "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
    static let dayNames = ["sun": 0, "mon": 1, "tue": 2, "wed": 3,
                           "thu": 4, "fri": 5, "sat": 6]

    // MARK: - 解析

    private typealias FieldSpec = (name: String, lo: Int, hi: Int, names: [String: Int])

    static func parse(_ expr: String) -> Result<CronExpression, ParseError> {
        let f = expr.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard f.count == 5 || f.count == 6 else { return .failure(.fieldCount(f.count)) }
        let hasSeconds = f.count == 6

        let specs: [FieldSpec] =
            (hasSeconds ? [("秒", 0, 59, [:] as [String: Int])] : []) + [
                ("分", 0, 59, [:]), ("时", 0, 23, [:]), ("日", 1, 31, [:]),
                ("月", 1, 12, monthNames), ("周", 0, 7, dayNames),
            ]

        var sets: [Set<Int>] = []
        for (i, spec) in specs.enumerated() {
            guard let s = field(f[i], spec.lo, spec.hi, names: spec.names) else {
                return .failure(.badField(position: i + 1, name: spec.name, text: f[i]))
            }
            sets.append(s)
        }

        let off = hasSeconds ? 1 : 0
        var w = sets[off + 4]
        if w.contains(7) { w.remove(7); w.insert(0) }   // 0 和 7 都表示周日

        return .success(CronExpression(
            seconds: hasSeconds ? sets[0] : nil,
            minutes: sets[off], hours: sets[off + 1], days: sets[off + 2],
            months: sets[off + 3], weekdays: w
        ))
    }

    /// 支持 `*`、`a`、`a-b`、`a,b,c`、`*/n`、`a-b/n`，以及 jan/mon 这类名称
    static func field(_ raw: String, _ lo: Int, _ hi: Int,
                      names: [String: Int] = [:]) -> Set<Int>? {
        guard !raw.isEmpty else { return nil }
        var out = Set<Int>()
        for part in raw.split(separator: ",") {
            var body = String(part)
            var step = 1
            if let slash = body.firstIndex(of: "/") {
                guard let s = Int(body[body.index(after: slash)...]), s > 0 else { return nil }
                step = s
                body = String(body[body.startIndex..<slash])
            }
            var from = lo, to = hi
            if body == "*" {
                // 全域
            } else if body.count > 1, let dash = body.dropFirst().firstIndex(of: "-") {
                guard let a = value(String(body[body.startIndex..<dash]), names),
                      let b = value(String(body[body.index(after: dash)...]), names)
                else { return nil }
                from = a; to = b
            } else {
                guard let v = value(body, names) else { return nil }
                from = v; to = v
            }
            guard from >= lo, to <= hi, from <= to else { return nil }
            out.formUnion(stride(from: from, through: to, by: step))
        }
        return out.isEmpty ? nil : out
    }

    private static func value(_ s: String, _ names: [String: Int]) -> Int? {
        Int(s) ?? names[s.lowercased()]
    }

    // MARK: - 未来执行时间

    /// 先按「天」过滤（月/日/周），命中的天再展开时分。
    /// 逐分钟暴力扫要走 50 万次 Calendar 计算，这样最多 400 次。
    func nextDates(after now: Date, count: Int = 10,
                   calendar: Calendar = .current, searchDays: Int = 400) -> [Date] {
        var results: [Date] = []
        var day = calendar.startOfDay(for: now)

        for _ in 0..<searchDays {
            let c = calendar.dateComponents([.day, .month, .weekday], from: day)
            let weekday = (c.weekday ?? 1) - 1          // Calendar 里 1=周日
            if months.contains(c.month ?? 0),
               days.contains(c.day ?? 0),
               weekdays.contains(weekday) {
                for h in hours.sorted() {
                    for m in minutes.sorted() {
                        guard let fire = calendar.date(bySettingHour: h, minute: m,
                                                       second: 0, of: day),
                              fire > now else { continue }
                        results.append(fire)
                        if results.count >= count { return results }
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }

    // MARK: - 人类可读

    var humanReadable: String {
        func list(_ set: Set<Int>, full: Int, suffix: String,
                  mapper: ((Int) -> String)? = nil) -> String? {
            guard set.count != full else { return nil }
            let sorted = set.sorted()
            if sorted.count > 6 { return "\(sorted.count) 个\(suffix.trimmingCharacters(in: .whitespaces))" }
            return sorted.map { mapper?($0) ?? "\($0)" }.joined(separator: "、") + suffix
        }

        var scope: [String] = []
        if let m = list(months, full: 12, suffix: " 月") { scope.append(m) }
        if let d = list(days, full: 31, suffix: " 号") { scope.append(d) }
        if let w = list(weekdays, full: 7, suffix: "",
                        mapper: { ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][$0 % 7] }) {
            scope.append(w)
        }

        let hourAll = hours.count == 24, minAll = minutes.count == 60
        let time: String
        if hourAll && minAll {
            time = "每分钟"
        } else if hourAll {
            time = "每小时的第 " + minutes.sorted().map(String.init).joined(separator: "、") + " 分"
        } else if minAll {
            time = hours.sorted().map(String.init).joined(separator: "、") + " 点每分钟"
        } else {
            let hs = hours.sorted(), ms = minutes.sorted()
            if hs.count <= 4 && ms.count <= 4 {
                time = hs.map { h in
                    ms.map { String(format: "%02d:%02d", h, $0) }.joined(separator: "、")
                }.joined(separator: "、")
            } else {
                time = "\(hs.count) 个小时 × \(ms.count) 个分钟"
            }
        }

        let sec = seconds.map { s -> String in
            s.count == 60 ? "（每秒）"
                          : "（秒：\(s.sorted().prefix(6).map(String.init).joined(separator: "、"))）"
        } ?? ""
        return "\(scope.isEmpty ? "每天" : scope.joined(separator: " ")) \(time) 执行\(sec)"
    }
}
