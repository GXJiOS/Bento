import Foundation
import CoreGraphics

/// 各平台图标尺寸表与 `Contents.json` 生成。纯数据+字符串，可脱离 App 验证。
enum IconSet {

    struct Spec {
        let filename: String
        let size: Int              // 像素
        var idiom: String = "universal"
        var scale: String? = nil   // "2x"
        var pointSize: String? = nil   // "20x20"
        var platform: String? = nil
    }

    enum Target: String, CaseIterable, Hashable {
        case iosModern, iosLegacy, macOS, favicon, android

        var label: String {
            switch self {
            case .iosModern: return "iOS（单尺寸）"
            case .iosLegacy: return "iOS（全套）"
            case .macOS:     return "macOS"
            case .favicon:   return "Favicon"
            case .android:   return "Android"
            }
        }

        var folder: String {
            switch self {
            case .iosModern, .iosLegacy: return "AppIcon.appiconset"
            case .macOS:   return "AppIcon.appiconset"
            case .favicon: return "favicon"
            case .android: return "android"
            }
        }

        var note: String {
            switch self {
            case .iosModern: return "Xcode 15+ 只需要一张 1024，系统自动降采样"
            case .iosLegacy: return "老工程 / 需要精确控制各尺寸时用"
            case .macOS:     return "含 16→512 各 @1x @2x，可同时导出 .icns"
            case .favicon:   return "含 .ico、apple-touch-icon 与 webmanifest"
            case .android:   return "mdpi → xxxhdpi 五档 mipmap"
            }
        }
    }

    // MARK: - 尺寸表

    static func specs(for target: Target) -> [Spec] {
        switch target {
        case .iosModern:
            return [Spec(filename: "icon-1024.png", size: 1024,
                         pointSize: "1024x1024", platform: "ios")]

        case .iosLegacy:
            // (点尺寸, 倍率, idiom)
            let table: [(Double, Int, String)] = [
                (20, 2, "iphone"), (20, 3, "iphone"),
                (29, 2, "iphone"), (29, 3, "iphone"),
                (40, 2, "iphone"), (40, 3, "iphone"),
                (60, 2, "iphone"), (60, 3, "iphone"),
                (20, 1, "ipad"), (20, 2, "ipad"),
                (29, 1, "ipad"), (29, 2, "ipad"),
                (40, 1, "ipad"), (40, 2, "ipad"),
                (76, 2, "ipad"), (83.5, 2, "ipad"),
                (1024, 1, "ios-marketing"),
            ]
            return table.map { pt, scale, idiom in
                let px = Int((pt * Double(scale)).rounded())
                let ptText = pt == pt.rounded() ? String(Int(pt)) : String(format: "%.1f", pt)
                return Spec(filename: "icon-\(ptText)@\(scale)x.png", size: px,
                            idiom: idiom, scale: "\(scale)x",
                            pointSize: "\(ptText)x\(ptText)")
            }

        case .macOS:
            let table: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2),
                                       (128, 1), (128, 2), (256, 1), (256, 2),
                                       (512, 1), (512, 2)]
            return table.map { pt, scale in
                Spec(filename: "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png",
                     size: pt * scale, idiom: "mac", scale: "\(scale)x",
                     pointSize: "\(pt)x\(pt)")
            }

        case .favicon:
            return [
                Spec(filename: "favicon-16x16.png", size: 16),
                Spec(filename: "favicon-32x32.png", size: 32),
                Spec(filename: "favicon-48x48.png", size: 48),
                Spec(filename: "apple-touch-icon.png", size: 180),
                Spec(filename: "android-chrome-192x192.png", size: 192),
                Spec(filename: "android-chrome-512x512.png", size: 512),
            ]

        case .android:
            return [
                Spec(filename: "mipmap-mdpi/ic_launcher.png", size: 48),
                Spec(filename: "mipmap-hdpi/ic_launcher.png", size: 72),
                Spec(filename: "mipmap-xhdpi/ic_launcher.png", size: 96),
                Spec(filename: "mipmap-xxhdpi/ic_launcher.png", size: 144),
                Spec(filename: "mipmap-xxxhdpi/ic_launcher.png", size: 192),
                Spec(filename: "play-store-512.png", size: 512),
            ]
        }
    }

    /// .ico 里打包的尺寸（ImageIO 写 ico 没问题）
    static let icoSizes = [16, 32, 48]

    /// macOS `.iconset` 的标准文件名表 —— iconutil 严格按这套命名识别尺寸
    static let iconsetTable: [(name: String, px: Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    enum ICNSError: LocalizedError {
        case encodeFailed
        case iconutilFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .encodeFailed: return "切图编码失败"
            case .iconutilFailed(let code, let msg):
                return "iconutil 退出码 \(code)\(msg.isEmpty ? "" : " · \(msg)")"
            }
        }
    }

    /// 用系统 iconutil 生成 .icns。
    ///
    /// 为什么不用 ImageIO：实测（macOS 26）它的 icns 写入器**只接受
    /// 16/32/128/256/512**，64 和 1024 会被静默丢弃，结果 Dock 最大档只能靠
    /// 512 放大，发糊。iconutil 能拿到完整 10 帧。这是非沙盒才有的选择。
    @discardableResult
    static func makeICNS(from image: CGImage, named name: String,
                         in dir: URL, keepIconset: Bool = false) -> Result<URL, ICNSError> {
        let iconset = dir.appendingPathComponent("\(name).iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        for (file, px) in iconsetTable {
            guard let scaled = ImageKit.resize(image, to: CGSize(width: px, height: px)),
                  let data = ImageKit.encode(scaled, to: .png, stripMetadata: true) else {
                return .failure(.encodeFailed)
            }
            try? data.write(to: iconset.appendingPathComponent(file))
        }

        let output = dir.appendingPathComponent("\(name).icns")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        let errPipe = Pipe()
        task.standardError = errPipe

        do { try task.run() } catch {
            return .failure(.iconutilFailed(-1, error.localizedDescription))
        }
        task.waitUntilExit()
        let errText = (try? errPipe.fileHandleForReading.readToEnd())
            .flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !keepIconset { try? FileManager.default.removeItem(at: iconset) }

        guard task.terminationStatus == 0 else {
            return .failure(.iconutilFailed(task.terminationStatus, errText))
        }
        return .success(output)
    }

    // MARK: - 附带文件

    static func contentsJSON(for target: Target) -> String? {
        let specs = specs(for: target)
        switch target {
        case .iosModern, .iosLegacy, .macOS:
            let images = specs.map { s -> String in
                var fields: [(String, String)] = [("filename", s.filename), ("idiom", s.idiom)]
                if let p = s.platform { fields.append(("platform", p)) }
                if let sc = s.scale { fields.append(("scale", sc)) }
                if let ps = s.pointSize { fields.append(("size", ps)) }
                let body = fields.sorted { $0.0 < $1.0 }
                    .map { "      \"\($0.0)\" : \"\($0.1)\"" }
                    .joined(separator: ",\n")
                return "    {\n\(body)\n    }"
            }.joined(separator: ",\n")
            return "{\n  \"images\" : [\n\(images)\n  ],\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"

        case .favicon:
            return nil
        case .android:
            return nil
        }
    }

    static func webManifest(appName: String) -> String {
        """
        {
          "name": "\(appName)",
          "short_name": "\(appName)",
          "icons": [
            { "src": "/android-chrome-192x192.png", "sizes": "192x192", "type": "image/png" },
            { "src": "/android-chrome-512x512.png", "sizes": "512x512", "type": "image/png" }
          ],
          "theme_color": "#ffffff",
          "background_color": "#ffffff",
          "display": "standalone"
        }
        """
    }

    static func faviconHTML() -> String {
        """
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
        <link rel="manifest" href="/site.webmanifest">
        """
    }
}
