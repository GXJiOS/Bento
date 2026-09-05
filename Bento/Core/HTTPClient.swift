import Foundation

/// HTTP 请求执行。
///
/// 比在线工具多给一样东西：`URLSessionTaskMetrics` 的**分段耗时**
/// （DNS / TCP / TLS / TTFB / 下载）。排查「慢」的时候，知道慢在哪一段
/// 比知道总共几毫秒有用得多。
enum HTTPClient {

    struct Header: Identifiable, Equatable {
        var id = UUID()
        var name: String
        var value: String
        var enabled = true
    }

    struct Request {
        var method = "GET"
        var url = ""
        var headers: [Header] = []
        var body = ""
        var followRedirects = true
        var timeout: TimeInterval = 30
    }

    struct Timing {
        var dns: Double?
        var tcp: Double?
        var tls: Double?
        var request: Double?
        var ttfb: Double?
        var download: Double?
        var total: Double = 0
        var reusedConnection = false
        var protocolName: String?

        /// 用于画耗时条
        var segments: [(String, Double)] {
            [("DNS", dns), ("TCP", tcp), ("TLS", tls), ("等待", ttfb), ("下载", download)]
                .compactMap { name, v in v.map { (name, $0) } }
                .filter { $0.1 > 0 }
        }
    }

    struct Response {
        var status = 0
        var statusText = ""
        var headers: [(String, String)] = []
        var body = Data()
        var timing = Timing()
        var error: String?
        var finalURL: String?
        var redirectCount = 0

        var bodyText: String { String(data: body, encoding: .utf8) ?? "" }

        var isJSON: Bool {
            headers.first { $0.0.lowercased() == "content-type" }?
                .1.lowercased().contains("json") ?? false
        }

        var prettyBody: String {
            guard isJSON,
                  let obj = try? JSONSerialization.jsonObject(with: body,
                                                              options: [.fragmentsAllowed]),
                  let out = try? JSONSerialization.data(
                    withJSONObject: obj,
                    options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]),
                  let s = String(data: out, encoding: .utf8)
            else { return bodyText }
            return s
        }

        var statusColorLevel: Int {   // 0 成功 1 重定向 2 客户端错 3 服务端错
            switch status {
            case 200..<300: return 0
            case 300..<400: return 1
            case 400..<500: return 2
            default: return status == 0 ? 3 : 3
            }
        }
    }

    // MARK: - 发送

    static func send(_ request: Request) async -> Response {
        var response = Response()

        guard let components = URLComponents(string: request.url.trimmingCharacters(in: .whitespaces)),
              components.scheme != nil, components.host != nil else {
            response.error = "URL 无效 —— 需要带 http:// 或 https://"
            return response
        }
        if components.scheme?.lowercased() == "http" {
            // 非沙盒 + 未开 ATS 例外时系统会拦明文请求，先说清楚
            response.error = nil
        }
        guard let url = components.url else {
            response.error = "URL 无法构造"
            return response
        }

        var req = URLRequest(url: url)
        req.httpMethod = request.method
        req.timeoutInterval = request.timeout
        for h in request.headers where h.enabled && !h.name.trimmed.isEmpty {
            req.setValue(h.value, forHTTPHeaderField: h.name.trimmed)
        }
        if !request.body.isEmpty, !["GET", "HEAD"].contains(request.method) {
            req.httpBody = Data(request.body.utf8)
        }

        let collector = MetricsCollector(followRedirects: request.followRedirects)
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: collector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, urlResponse) = try await session.data(for: req)
            response.body = data
            if let http = urlResponse as? HTTPURLResponse {
                response.status = http.statusCode
                response.statusText = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                response.headers = http.allHeaderFields
                    .compactMap { k, v in (k as? String).map { ($0, "\(v)") } }
                    .sorted { $0.0.lowercased() < $1.0.lowercased() }
                response.finalURL = http.url?.absoluteString
            }
            response.timing = collector.timing
            response.redirectCount = collector.redirectCount
        } catch {
            let ns = error as NSError
            response.error = friendly(ns)
            response.timing = collector.timing
        }
        return response
    }

    private static func friendly(_ error: NSError) -> String {
        switch error.code {
        case NSURLErrorCannotFindHost:      return "DNS 解析失败 —— 域名不存在或网络不通"
        case NSURLErrorCannotConnectToHost: return "连不上主机 —— 端口没开或被防火墙拦了"
        case NSURLErrorTimedOut:            return "请求超时"
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateHasUnknownRoot:
            return "TLS 失败 —— 证书有问题，可以用「证书检查」看一眼"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "ATS 拦了明文 HTTP —— 换 https，或在 Info.plist 里加例外"
        case NSURLErrorNotConnectedToInternet: return "没有网络连接"
        default:
            return "\(error.localizedDescription)（code \(error.code)）"
        }
    }

    /// 收集分段耗时；顺便按需拦截重定向
    private final class MetricsCollector: NSObject, URLSessionTaskDelegate {
        var timing = Timing()
        var redirectCount = 0
        private let followRedirects: Bool

        init(followRedirects: Bool) { self.followRedirects = followRedirects }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didFinishCollecting metrics: URLSessionTaskMetrics) {
            timing.total = metrics.taskInterval.duration * 1000
            guard let m = metrics.transactionMetrics.last else { return }

            func gap(_ a: Date?, _ b: Date?) -> Double? {
                guard let a, let b else { return nil }
                return b.timeIntervalSince(a) * 1000
            }
            timing.dns = gap(m.domainLookupStartDate, m.domainLookupEndDate)
            timing.tcp = gap(m.connectStartDate, m.secureConnectionStartDate ?? m.connectEndDate)
            timing.tls = gap(m.secureConnectionStartDate, m.secureConnectionEndDate)
            timing.request = gap(m.requestStartDate, m.requestEndDate)
            timing.ttfb = gap(m.requestEndDate, m.responseStartDate)
            timing.download = gap(m.responseStartDate, m.responseEndDate)
            timing.reusedConnection = m.isReusedConnection
            timing.protocolName = m.networkProtocolName
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            redirectCount += 1
            return followRedirects ? request : nil
        }
    }
}
