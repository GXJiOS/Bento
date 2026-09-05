import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// macOS 图标规范：1024 画布，本体 824 居中（四边各留 100），圆角约为本体的 22.5%
let CANVAS: CGFloat = 1024
let BODY: CGFloat = 824
let INSET: CGFloat = (CANVAS - BODY) / 2
let RADIUS: CGFloat = BODY * 0.225

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

// App 里的 6 个分类色（Apple 系统色）
let BLUE: UInt32 = 0x0A84FF, PURPLE: UInt32 = 0xBF5AF2, PINK: UInt32 = 0xFF375F
let GREEN: UInt32 = 0x30D158, TEAL: UInt32 = 0x64D2FF, ORANGE: UInt32 = 0xFF9F0A

func ctx() -> CGContext {
    CGContext(data: nil, width: Int(CANVAS), height: Int(CANVAS), bitsPerComponent: 8,
              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// 图标本体：底色 + 顶部高光 + 底部投影
func drawBase(_ c: CGContext, top: UInt32, bottom: UInt32, highlight: Bool = true) {
    let body = CGRect(x: INSET, y: INSET, width: BODY, height: BODY)

    // 投影
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -18), blur: 40,
                color: hex(0x000000, 0.34))
    c.addPath(rounded(body, RADIUS))
    c.setFillColor(hex(bottom))
    c.fillPath()
    c.restoreGState()

    // 底色渐变
    c.saveGState()
    c.addPath(rounded(body, RADIUS))
    c.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [hex(top), hex(bottom)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: 0, y: CANVAS),
                         end: CGPoint(x: 0, y: 0), options: [])
    // 顶部高光：macOS 图标那种「一层玻璃」的感觉
    if highlight {
        let hl = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            colors: [hex(0xFFFFFF, 0.16), hex(0xFFFFFF, 0)] as CFArray,
                            locations: [0, 1])!
        c.drawLinearGradient(hl, start: CGPoint(x: 0, y: CANVAS - INSET),
                             end: CGPoint(x: 0, y: CANVAS - INSET - BODY * 0.45), options: [])
    }
    c.restoreGState()

    // 内描边，让边缘更利落
    c.addPath(rounded(body.insetBy(dx: 1, dy: 1), RADIUS - 1))
    c.setStrokeColor(hex(0xFFFFFF, 0.10))
    c.setLineWidth(2)
    c.strokePath()
}

/// bento grid：不对称格子。这是整个图标的主体隐喻。
/// 单位坐标 (x, y, w, h)，原点左上，范围 0...1
let GRID: [(CGFloat, CGFloat, CGFloat, CGFloat, UInt32)] = [
    (0.00, 0.00, 0.56, 0.56, BLUE),     // 左上大块
    (0.60, 0.00, 0.40, 0.34, PURPLE),   // 右上横条
    (0.60, 0.38, 0.40, 0.62, PINK),     // 右侧竖条
    (0.00, 0.60, 0.26, 0.40, GREEN),    // 左下小块
    (0.30, 0.60, 0.26, 0.40, ORANGE),   // 中下小块
]

func drawGrid(_ c: CGContext, inset: CGFloat, colors: [UInt32]? = nil,
              alpha: CGFloat = 1, cellRadius: CGFloat = 0.11) {
    let area = CGRect(x: INSET + inset, y: INSET + inset,
                      width: BODY - inset * 2, height: BODY - inset * 2)
    for (i, cell) in GRID.enumerated() {
        let (ux, uy, uw, uh, defaultColor) = cell
        let color = colors.map { $0[i % $0.count] } ?? defaultColor
        // 单位坐标是左上原点，CoreGraphics 是左下原点，y 要翻过来
        let r = CGRect(x: area.minX + ux * area.width,
                       y: area.minY + (1 - uy - uh) * area.height,
                       width: uw * area.width,
                       height: uh * area.height)
        c.addPath(rounded(r, area.width * cellRadius))
        c.setFillColor(hex(color, alpha))
        c.fillPath()
    }
}

/// 输出目录：默认项目里的 icon/，跑的时候可以用第一个参数覆盖
let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/icon"

func write(_ image: CGImage, _ name: String) {
    let dir = URL(fileURLWithPath: outputDir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("  \(name).png")
}

// ── A：深底 + 彩色 bento 格子（最贴主题）──
do {
    let c = ctx()
    drawBase(c, top: 0x252734, bottom: 0x0F1015)
    drawGrid(c, inset: 150)
    write(c.makeImage()!, "source-1024")
}

// 各尺寸缩略图，用来检查小尺寸下糊不糊
func resize(_ img: CGImage, _ size: Int) -> CGImage {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
    return c.makeImage()!
}

let dir = URL(fileURLWithPath: outputDir)
for name in ["source-1024"] {
    guard let src = CGImageSourceCreateWithURL(
            dir.appendingPathComponent("\(name).png") as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    _ = img   // 各尺寸切图交给 make-appicon.swift（复用 App 里的 IconSet）
}
print("\n✓ 生成完毕")
