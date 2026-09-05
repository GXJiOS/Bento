// 把 icon/source-1024.png 切成 Xcode 的 AppIcon.appiconset。
// 复用 App 自己的 ImageKit + IconSet —— 用自己的工具做自己的图标。
//
//   swift icon/make-appicon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = FileManager.default.currentDirectoryPath
let sourceURL = URL(fileURLWithPath: "\(root)/icon/source-1024.png")
let assets = URL(fileURLWithPath: "\(root)/Bento/Assets.xcassets")
let appicon = assets.appendingPathComponent("AppIcon.appiconset")

guard let data = try? Data(contentsOf: sourceURL),
      let src = ImageKit.image(from: data) else {
    print("✗ 读不到 \(sourceURL.path)"); exit(1)
}
print("源图 \(src.width)×\(src.height)")

try? FileManager.default.createDirectory(at: appicon, withIntermediateDirectories: true)

// 资源目录根 Contents.json
let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try? rootContents.write(to: assets.appendingPathComponent("Contents.json"),
                        atomically: true, encoding: .utf8)

// 各尺寸 PNG
var n = 0
for spec in IconSet.specs(for: .macOS) {
    guard let scaled = ImageKit.resize(src, to: CGSize(width: spec.size, height: spec.size)),
          let png = ImageKit.encode(scaled, to: .png, stripMetadata: true) else {
        print("✗ \(spec.filename)"); continue
    }
    try? png.write(to: appicon.appendingPathComponent(spec.filename))
    print("  \(spec.filename.padding(toLength: 24, withPad: " ", startingAt: 0)) \(spec.size)px")
    n += 1
}

// appiconset 的 Contents.json
if let json = IconSet.contentsJSON(for: .macOS) {
    try? json.write(to: appicon.appendingPathComponent("Contents.json"),
                    atomically: true, encoding: .utf8)
    n += 1
}

// 顺带出一份 .icns（走 iconutil，10 帧完整）
switch IconSet.makeICNS(from: src, named: "Bento", in: URL(fileURLWithPath: "\(root)/icon")) {
case .success(let url):
    let frames = (try? Data(contentsOf: url)).flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .map { CGImageSourceGetCount($0) } ?? 0
    print("\n  Bento.icns  \(frames) 帧")
case .failure(let e):
    print("\n  ✗ .icns 失败：\(e.localizedDescription)")
}

print("\n✓ 写了 \(n) 个文件到 Bento/Assets.xcassets/AppIcon.appiconset/")
