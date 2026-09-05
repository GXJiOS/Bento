import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 图像读写。只依赖 ImageIO / CoreGraphics，不碰 AppKit 与 SwiftUI，
/// 所以能脱离 App 直接跑验证。
enum ImageKit {

    // MARK: - 元信息

    struct Info {
        var pixelWidth = 0
        var pixelHeight = 0
        var dpi: Double = 72
        var hasAlpha = false
        var colorModel = "—"
        var depth = 8
        var utType: UTType?
        var byteCount = 0
        var frameCount = 1
        /// 原始元数据字典，EXIF 工具用
        var properties: [String: Any] = [:]

        var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
        var megapixels: Double { Double(pixelWidth * pixelHeight) / 1_000_000 }
        var aspect: String {
            guard pixelWidth > 0, pixelHeight > 0 else { return "—" }
            let g = Self.gcd(pixelWidth, pixelHeight)
            return "\(pixelWidth / g):\(pixelHeight / g)"
        }
        var isAnimated: Bool { frameCount > 1 }

        private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    }

    // MARK: - 加载

    static func source(from data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, nil)
    }

    static func info(from data: Data) -> Info? {
        guard let src = source(from: data) else { return nil }
        var info = Info()
        info.byteCount = data.count
        info.frameCount = CGImageSourceGetCount(src)
        if let t = CGImageSourceGetType(src) as String? {
            info.utType = UTType(t)
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else {
            return info
        }
        info.properties = props
        info.pixelWidth = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        info.pixelHeight = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        info.hasAlpha = props[kCGImagePropertyHasAlpha as String] as? Bool ?? false
        info.depth = props[kCGImagePropertyDepth as String] as? Int ?? 8
        info.colorModel = props[kCGImagePropertyColorModel as String] as? String ?? "—"
        if let dpi = props[kCGImagePropertyDPIWidth as String] as? Double, dpi > 0 {
            info.dpi = dpi
        }
        return info
    }

    static func image(from data: Data, index: Int = 0) -> CGImage? {
        guard let src = source(from: data) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, index, [
            kCGImageSourceShouldCache: true,
        ] as CFDictionary)
    }

    // MARK: - 可写格式

    /// 系统实际支持写出的类型 —— 直接问 ImageIO，不靠猜
    static var writableTypes: [UTType] {
        (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
            .compactMap { UTType($0) }
    }

    static func canWrite(_ type: UTType) -> Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type.identifier)
    }

    /// 常用导出格式，按系统实际可写性过滤。
    /// 实测（macOS 26）：HEIC / AVIF / ICNS / ICO 都能写，**WebP 只能读不能写**，
    /// 所以它不会出现在这个列表里。
    static var exportTypes: [UTType] {
        [.png, .jpeg, .heic, UTType("public.avif"), .tiff, .gif, .bmp, UTType("com.microsoft.ico")]
            .compactMap { $0 }
            .filter { canWrite($0) }
    }

    /// 有损格式才需要质量滑杆
    static func isLossy(_ type: UTType) -> Bool {
        [UTType.jpeg.identifier, "public.heic", "public.avif", "public.jpeg-2000"]
            .contains(type.identifier)
    }

    // MARK: - 编码

    /// - Parameters:
    ///   - quality: 0...1，仅对有损格式（JPEG / HEIC / WebP）生效
    ///   - stripMetadata: 去掉 EXIF / GPS 等，发图前常用
    static func encode(_ image: CGImage, to type: UTType,
                       quality: Double = 0.8, stripMetadata: Bool = false,
                       sourceProperties: [String: Any]? = nil) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out as CFMutableData, type.identifier as CFString, 1, nil) else { return nil }

        var options: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: quality,
        ]
        if !stripMetadata, let src = sourceProperties {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary,
                        kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary] {
                if let v = src[key as String] { options[key as String] = v }
            }
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    // MARK: - 缩放

    /// 高质量重采样。图标切图靠它，插值质量直接决定小尺寸下糊不糊。
    static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0 else { return nil }
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// 按最长边等比缩放，不放大
    static func fit(_ image: CGImage, maxEdge: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxEdge else { return image }
        let scale = Double(maxEdge) / Double(longest)
        return resize(image, to: CGSize(width: Double(image.width) * scale,
                                        height: Double(image.height) * scale))
    }

    // MARK: - EXIF

    struct MetadataGroup {
        let title: String
        let rows: [(String, String)]
    }

    /// 分组后的可读元数据。GPS 单列一组，因为发图前最该确认的就是它。
    static func metadata(from props: [String: Any]) -> [MetadataGroup] {
        var groups: [MetadataGroup] = []

        func group(_ title: String, _ key: CFString, _ mapping: [(CFString, String)]) {
            guard let dict = props[key as String] as? [String: Any] else { return }
            var rows: [(String, String)] = []
            for (k, label) in mapping {
                if let v = dict[k as String] { rows.append((label, describe(v))) }
            }
            // 映射表没覆盖到的键也列出来，别让用户以为没有
            let known = Set(mapping.map { $0.0 as String })
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) where !known.contains(k) {
                rows.append((k.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""),
                             describe(v)))
            }
            if !rows.isEmpty { groups.append(MetadataGroup(title: title, rows: rows)) }
        }

        group("EXIF", kCGImagePropertyExifDictionary, [
            (kCGImagePropertyExifDateTimeOriginal, "拍摄时间"),
            (kCGImagePropertyExifLensModel, "镜头"),
            (kCGImagePropertyExifFNumber, "光圈 f/"),
            (kCGImagePropertyExifExposureTime, "快门 (s)"),
            (kCGImagePropertyExifISOSpeedRatings, "ISO"),
            (kCGImagePropertyExifFocalLength, "焦距 (mm)"),
            (kCGImagePropertyExifFocalLenIn35mmFilm, "等效焦距"),
            (kCGImagePropertyExifExposureBiasValue, "曝光补偿"),
        ])
        group("相机", kCGImagePropertyTIFFDictionary, [
            (kCGImagePropertyTIFFMake, "厂商"),
            (kCGImagePropertyTIFFModel, "型号"),
            (kCGImagePropertyTIFFSoftware, "软件"),
            (kCGImagePropertyTIFFOrientation, "方向"),
        ])
        group("GPS 位置", kCGImagePropertyGPSDictionary, [
            (kCGImagePropertyGPSLatitude, "纬度"),
            (kCGImagePropertyGPSLatitudeRef, "南北"),
            (kCGImagePropertyGPSLongitude, "经度"),
            (kCGImagePropertyGPSLongitudeRef, "东西"),
            (kCGImagePropertyGPSAltitude, "海拔 (m)"),
            (kCGImagePropertyGPSDateStamp, "GPS 日期"),
        ])
        group("IPTC", kCGImagePropertyIPTCDictionary, [
            (kCGImagePropertyIPTCKeywords, "关键词"),
            (kCGImagePropertyIPTCCopyrightNotice, "版权"),
            (kCGImagePropertyIPTCByline, "作者"),
        ])
        return groups
    }

    static func hasGPS(_ props: [String: Any]) -> Bool {
        (props[kCGImagePropertyGPSDictionary as String] as? [String: Any])?.isEmpty == false
    }

    private static func describe(_ v: Any) -> String {
        switch v {
        case let a as [Any]: return a.map { describe($0) }.joined(separator: ", ")
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(format: "%g", d)
        default: return "\(v)"
        }
    }

    // MARK: - 格式化

    static func byteString(_ n: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }
}
