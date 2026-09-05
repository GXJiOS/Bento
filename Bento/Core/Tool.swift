import SwiftUI

// MARK: - 分类

enum ToolCategory: String, CaseIterable, Identifiable, Hashable {
    case encoding      // 编解码
    case formatting    // 格式化 / 代码
    case style         // 样式与设计
    case image         // 图像与资源
    case system        // 系统集成
    case network       // 网络

    var id: String { rawValue }

    var title: String {
        switch self {
        case .encoding:   return "编解码"
        case .formatting: return "格式化 / 代码"
        case .style:      return "样式与设计"
        case .image:      return "图像与资源"
        case .system:     return "系统集成"
        case .network:    return "网络"
        }
    }

    var symbol: String {
        switch self {
        case .encoding:   return "chevron.left.forwardslash.chevron.right"
        case .formatting: return "curlybraces"
        case .style:      return "paintpalette"
        case .image:      return "photo"
        case .system:     return "cpu"
        case .network:    return "globe"
        }
    }

    /// 分类语义色 —— Apple 系统色，自动适配主题
    var tint: Color {
        switch self {
        case .encoding:   return Color(nsColor: .systemBlue)
        case .formatting: return Color(nsColor: .systemPurple)
        case .style:      return Color(nsColor: .systemPink)
        case .image:      return Color(nsColor: .systemGreen)
        case .system:     return Color(nsColor: .systemTeal)
        case .network:    return Color(nsColor: .systemOrange)
        }
    }

    /// 该分类下的工具数，侧栏右侧显示。
    /// 动态取自注册表 —— 写死的话，合并或拆分工具之后就会对不上
    /// （Phase 4 把「压缩」「格式转换」合并、「.icns」并入图标套件之后就发生过）。
    var toolCount: Int { ToolRegistry.items(in: self).count }
}

// MARK: - 布局模板

/// 四个模板覆盖全部工具。加工具时只选其一，不自己写页面骨架。
enum ToolLayout {
    case dual      // ≈24：左右双栏，可逆工具带 ⇅
    case stacked   // ≈8 ：上下堆叠，输入需要整行宽度
    case form      // ≈14：一入多出，逐行复制
    case canvas    // ≈8 ：参数 + 实时预览
}

// MARK: - 元数据

struct ToolMeta: Identifiable, Hashable {
    let id: String
    let name: String
    let category: ToolCategory
    let layout: ToolLayout
    let symbol: String
    /// 命令面板模糊匹配用：英文缩写 + 拼音首字母
    var aliases: [String] = []

    static func == (a: ToolMeta, b: ToolMeta) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 工具协议

/// 一个工具 = 一个 View + 一份静态 meta。
/// 新增工具：建一个文件实现 ToolView，在 ToolRegistry.all 里加一行。工程文件不用动
/// （target 用 file system synchronized group，目录即 target）。
protocol ToolView: View {
    static var meta: ToolMeta { get }
    init()
}

/// 类型擦除后的注册项 —— 让不同 ToolView 能装进同一个数组
struct ToolEntry: Identifiable {
    let meta: ToolMeta
    let build: () -> AnyView

    var id: String { meta.id }

    init<T: ToolView>(_ type: T.Type) {
        self.meta = T.meta
        self.build = { AnyView(T()) }
    }
}
