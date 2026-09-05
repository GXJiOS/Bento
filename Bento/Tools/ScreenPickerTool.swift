import SwiftUI
import AppKit

struct ScreenPickerTool: ToolView {
    static let meta = ToolMeta(
        id: "picker", name: "屏幕取色", category: .style, layout: .form,
        symbol: "eyedropper.halffull",
        aliases: ["picker", "eyedropper", "sampler", "pmqs", "quse"]
    )

    struct Pick: Identifiable {
        let id = UUID()
        let color: ColorMath.RGB
        let index: Int
    }

    @State private var picks: [Pick] = []
    @State private var format: Format = .hex

    enum Format: Hashable, CaseIterable {
        case hex, rgb, swiftui, appkit
        var label: String {
            switch self {
            case .hex: return "HEX"
            case .rgb: return "RGB"
            case .swiftui: return "SwiftUI"
            case .appkit: return "AppKit"
            }
        }
    }

    init() {}

    var body: some View {
        StackLayout(status: status) {
            Button {
                pick()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eyedropper")
                    Text("取色")
                    Keycap(text: "⌥⌘P")
                }
            }
            .bentoButton(prominent: true)
            .keyboardShortcut("p", modifiers: [.option, .command])

            OptionLabel(text: "复制为")
            BentoSegments(options: Format.allCases.map { ($0, $0.label) }, selection: $format)
            Spacer()
            Button("清空") { picks.removeAll() }
                .bentoButton()
                .disabled(picks.isEmpty)
        } content: {
            if picks.isEmpty {
                Card {
                    VStack(spacing: 10) {
                        Image(systemName: "eyedropper.halffull")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("点「取色」后，鼠标会变成放大镜")
                            .font(Tokens.body).foregroundStyle(.secondary)
                        Text("系统级吸管，可以取任意窗口甚至桌面上的颜色")
                            .font(Tokens.small).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Card(title: "最近取色", dot: ToolCategory.style.tint,
                     meta: "\(picks.count) 个 · 点行复制") {
                    ResultRows(rows: rows, keyWidth: 128)
                        .frame(maxHeight: .infinity)
                }

                Card(title: "色卡", dot: ToolCategory.image.tint, meta: "点击复制 HEX") {
                    SwatchStrip(items: picks.prefix(12).map { ("\($0.index)", $0.color) },
                                height: 44)
                        .padding(.horizontal, Tokens.padCard)
                        .padding(.bottom, Tokens.padCard)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: -

    private func pick() {
        NSColorSampler().show { picked in
            guard let picked else { return }
            let c = picked.usingColorSpace(.sRGB) ?? picked
            let rgb = ColorMath.RGB(r: Double(c.redComponent),
                                    g: Double(c.greenComponent),
                                    b: Double(c.blueComponent))
            picks.insert(Pick(color: rgb, index: picks.count + 1), at: 0)
            if picks.count > 20 { picks.removeLast() }
        }
    }

    private var rows: [(String, String)] {
        picks.map { p in
            let (r, g, b) = p.color.bytes
            let value: String
            switch format {
            case .hex: value = p.color.hex
            case .rgb: value = "rgb(\(r), \(g), \(b))"
            case .swiftui:
                value = String(format: "Color(.sRGB, red: %.3f, green: %.3f, blue: %.3f, opacity: 1)",
                               p.color.r, p.color.g, p.color.b)
            case .appkit:
                value = String(format: "NSColor(srgbRed: %.3f, green: %.3f, blue: %.3f, alpha: 1)",
                               p.color.r, p.color.g, p.color.b)
            }
            let hsl = ColorMath.toHSL(p.color)
            return ("#\(p.index)  \(p.color.hex)",
                    "\(value)      H\(Int(hsl.h)) S\(Int(hsl.s * 100)) L\(Int(hsl.l * 100))")
        }
    }

    private var status: StatusLine {
        guard let latest = picks.first else {
            return StatusLine(level: .idle, text: "还没有取色 · NSColorSampler 系统吸管",
                              trailing: "sRGB", trailingKey: "⌄")
        }
        let white = ColorMath.RGB(r: 1, g: 1, b: 1)
        let black = ColorMath.RGB(r: 0, g: 0, b: 0)
        let onWhite = ColorMath.contrast(latest.color, white)
        let onBlack = ColorMath.contrast(latest.color, black)
        let nearest = ColorMath.nearestTailwind(latest.color)
        return StatusLine(
            level: .ok,
            text: "\(latest.color.hex) · 对白 \(String(format: "%.1f", onWhite)):1 对黑 \(String(format: "%.1f", onBlack)):1 · 近 \(nearest.name)",
            trailing: "sRGB", trailingKey: "⌄"
        )
    }
}
