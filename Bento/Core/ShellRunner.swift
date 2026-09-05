import Foundation

/// 跑外部命令。DNS / Ping / 证书这些，调系统自带的 `dig` `ping` `openssl`
/// 比用 Network.framework 自己拼省事得多 —— 这是非沙盒才有的选择。
enum ShellRunner {

    struct Output {
        var stdout = ""
        var stderr = ""
        var code: Int32 = -1
        var duration: TimeInterval = 0
        var timedOut = false

        var succeeded: Bool { code == 0 && !timedOut }
        /// 命令失败时，stderr 通常比 stdout 有用
        var text: String { stdout.isEmpty ? stderr : stdout }
    }

    /// 常用工具的绝对路径。不走 PATH 查找 —— 避免被用户环境里的同名脚本劫持。
    enum Tool: String {
        case dig = "/usr/bin/dig"
        case ping = "/sbin/ping"
        case host = "/usr/bin/host"
        case openssl = "/usr/bin/openssl"
        case whois = "/usr/bin/whois"
        case curl = "/usr/bin/curl"

        var exists: Bool { FileManager.default.isExecutableFile(atPath: rawValue) }
    }

    /// - Important: 管道读取必须放到后台线程。输出超过 pipe 缓冲区（64KB）时，
    ///   在主线程 `waitUntilExit` 会和写端互相等待，直接死锁。
    static func run(_ tool: Tool, _ args: [String],
                    stdin: String? = nil, timeout: TimeInterval = 10) -> Output {
        guard tool.exists else {
            return Output(stderr: "找不到 \(tool.rawValue)", code: -1)
        }

        var result = Output()
        let start = Date()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool.rawValue)
        task.arguments = args

        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        if let stdin {
            let inPipe = Pipe()
            task.standardInput = inPipe
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inPipe.fileHandleForWriting.closeFile()
        }

        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do { try task.run() } catch {
            return Output(stderr: error.localizedDescription, code: -1)
        }

        // 超时就 SIGTERM，再等一小会儿不退就 SIGKILL
        let timer = DispatchWorkItem {
            if task.isRunning {
                result.timedOut = true
                task.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        task.waitUntilExit()
        timer.cancel()
        group.wait()

        result.stdout = String(data: outData, encoding: .utf8) ?? ""
        result.stderr = String(data: errData, encoding: .utf8) ?? ""
        result.code = task.terminationStatus
        result.duration = Date().timeIntervalSince(start)
        return result
    }

    /// 异步版，UI 里用这个，别把主线程卡住
    static func runAsync(_ tool: Tool, _ args: [String],
                         stdin: String? = nil, timeout: TimeInterval = 10) async -> Output {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: run(tool, args, stdin: stdin, timeout: timeout))
            }
        }
    }

    /// 主机名 / IP 的基本校验 —— 拼进命令行之前先挡一道，
    /// 虽然 Process 不走 shell（不存在注入），但可以避免把明显错的输入发出去
    static func isValidHost(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 253, !t.contains(" ") else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:_")
        return t.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
