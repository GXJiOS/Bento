# Bento

本地自用的 macOS 工具集。SwiftUI + AppKit，非沙盒，不分发。

- Bundle ID `com.gcdm.bento` · 部署目标 macOS 14.0 · Swift 5 语言模式
- 设计原型：`../toolbox-design/prototype.html`（视觉规范的唯一事实来源）

## 安装 / 更新

```bash
./install.sh          # 编译 Release → 装到 /Applications → 重新注册 → 启动
```

改完代码跑这一条就行。开发时想快速试可以直接：

```bash
xcodebuild -project Bento.xcodeproj -scheme Bento -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Bento-*/Build/Products/Debug/Bento.app
```

**注意**：Services 菜单和 CLI wrapper 都记的是 App 的绝对路径。如果只从
DerivedData 运行，`xcodebuild clean` 之后这些会失效 —— 所以日常用的那份要装在
`/Applications`。

### CLI 伴生（可选，装一次）

`/usr/local/bin` 默认是 `root:wheel`，需要管理员权限：

```bash
sudo mkdir -p /usr/local/bin && \
  printf '#!/bin/sh\nexec "/Applications/Bento.app/Contents/MacOS/Bento" "$@"\n' | \
  sudo tee /usr/local/bin/bento >/dev/null && sudo chmod +x /usr/local/bin/bento
```

## 工程约定

**target 用 file system synchronized group**（`PBXFileSystemSynchronizedRootGroup`）——
`Bento/` 目录下的 `.swift` 会自动进 Sources 阶段。**新增文件不需要改 `project.pbxproj`**，
这是这个项目唯一豁免「新增 Swift 文件必须更新 pbxproj」那条规则的地方。

## 新增一个工具（三步）

1. 在 `Bento/Tools/` 建一个文件，实现 `ToolView`：

```swift
struct FooTool: ToolView {
    static let meta = ToolMeta(
        id: "foo", name: "Foo 工具", category: .encoding, layout: .dual,
        symbol: "arrow.left.arrow.right",       // SF Symbol
        aliases: ["foo", "fgj"]                 // 英文缩写 + 拼音首字母，命令面板搜索用
    )
    init() {}
    var body: some View { /* 用下表选中的模板 */ }
}
```

2. 在 `Core/ToolRegistry.swift` 的 `all` 数组加一行 `ToolEntry(FooTool.self)`。
3. 从 `planned` 数组里删掉对应的占位项。

## 四个布局模板

| 模板 | 用 | 覆盖 |
|---|---|---|
| `DualLayout` | 左右双栏，可逆工具传 `onSwap` | Base64、URL、转义、格式化…（≈24） |
| `StackLayout` | 纵向堆叠若干 `Card` | 正则、Diff、Markdown（≈8） |
| `StackLayout` | 输入卡 + `ResultRows` | 颜色、哈希、时间戳（≈14） |
| `StackLayout` | 画布卡 + `ResultRows` | 缓动、阴影、渐变（≈8） |

三者共用 `ToolScaffold`（灰底 + 选项条 + 内容 + 状态行）。工具**不写自己的页面骨架**。

常用零件：`Card` / `CardFooter` / `OptionBar` / `CodeArea` / `ResultRows` /
`BentoSegments` / `BentoCheck` / `Keycap` / `CopyButton` / `StatusLine`。
按钮用 `.bentoButton(prominent:plain:)`。

**编解码类工具直接用 `ConverterView`** —— 它把 `.dual` 的骨架（选项条 + 输入卡 +
输出卡 + 粘贴/清空/复制/存文件 + 状态行）全包了，工具只剩一个转换函数：

```swift
ConverterView(input: $input, output: result.text, error: result.error,
              okText: direction.okText,
              onSwap: { ... },              // 可逆工具才传，传了才出现 ⇅
              onLoadFile: { url in ... }) {  // 传了才出现「载入文件…」
    OptionLabel(text: "方向")
    DirectionPicker(direction: $direction)
    BentoCheck(label: "URL-safe", isOn: $urlSafe)
}
```

## 怎么验证（重要）

**不要用 `osascript ... keystroke` 驱动 UI 来做验证。** 前台很容易被别的 App 抢走，
按键会静默发到别处，测试全绿但其实什么都没点到 —— 这个坑踩过一次，
导致前几个阶段的「逐个打开工具」回归其实只证明了进程没崩溃。

可靠的三种方式：

1. **纯逻辑直接跑**（首选）：Core 里的引擎只依赖 Foundation，
   `cat Bento/Core/X.swift > /tmp/t.swift && echo '...' >> /tmp/t.swift && swift /tmp/t.swift`
2. **渲染验证**：改 `state.json` 的 `selectedToolID` 再启动，能真正把某个工具的
   View 渲染出来，然后检查进程存活与崩溃日志
3. **AX 点菜单项**（不是模拟按键）：
   `click menu item "X" of menu 1 of menu bar item "View" of menu bar 1`

系统级能力另有各自的证据：Services 查 `pbs -dump_pboard`、
全局热键查窗口列表里有没有多出 `AXSystemDialog`、CLI 直接跑二进制。

## 纯逻辑放 Core

`JSONInference` / `YAMLLite` / `CronExpression` / `ColorMath` / `CSSConverter` /
`ImageKit` / `IconSet` / `ContentDetector` / `HeaderAnalyzer` / `ShellRunner`
都是只依赖 Foundation（或 ImageIO）的纯逻辑，
**不碰 SwiftUI**。这样能脱离 App 直接跑验证：

```bash
cat Bento/Core/CronExpression.swift > /tmp/t.swift
echo 'print(try! CronExpression.parse("30 9 * * 1-5"))' >> /tmp/t.swift
swift /tmp/t.swift
```

写新工具时，凡是「算法」都往 Core 放，View 里只留 UI —— 光靠 build 通过和点开不崩溃
发现不了算错，这三个引擎的 bug 全是这么测出来的。

## CLI 伴生

App 的主二进制同时也是命令行工具 —— `BentoMain.main()` 在启动 SwiftUI 之前先问
`CLIRunner.runIfNeeded()`，命中就处理完直接 `exit`，界面一次都不会建。

```bash
bento b64 "Hello, 世界"
echo '{"b":2,"a":1}' | bento json
pbpaste | bento detect
```

在「CLI 伴生」工具页里点安装，会往 `/usr/local/bin/bento` 写一个 exec 到 App
二进制的 wrapper。该目录不可写时会把 `sudo` 命令回显出来让你手动执行。

## 数据存放

`~/Library/Application Support/Bento/`，全是 JSON，可直接打开看：

| 文件 | 内容 |
|---|---|
| `state.json` | 选中工具、收藏、最近、展开的分类、隐藏的工具 |
| `settings.json` | 热键、剪贴板、输入记忆等偏好 |
| `memory.json` | 每个工具上次的输入（只存当前值，>32KB 不存） |
| `clipboard.json` | 剪贴板历史 —— **默认不写盘**，要在设置里显式打开 |

设置 → 数据里可以整包导出/导入，换机器时直接搬。

## 设计令牌

全部在 `Core/DesignTokens.swift`，与原型规范页 1:1。改视觉只改这一个文件。

- 语义色（accent / separator / label / system*）读系统，**不写死**
- 层次色（灰底 / 卡片 / 凹槽）用 `dynamicProvider` 写死原型调好的值 ——
  系统没有正好的语义（dark 下 `controlBackgroundColor` 比 `underPageBackgroundColor`
  更深，与「卡片浮在灰底上」相反）

## 系统能力实测记录

写这批工具时实测出来的、文档上查不到的限制：

| 事 | 结论 |
|---|---|
| ImageIO 可写格式 | HEIC / AVIF / ICNS / ICO 都能写；**WebP 只能读不能写** |
| ImageIO 写 `.icns` | **只接受 16/32/128/256/512**，64 和 1024 被静默丢弃 → 改用 `/usr/bin/iconutil`，拿到完整 10 帧 |
| 屏幕取色 | `NSColorSampler` 十行搞定，不需要屏幕录制权限 |
| 全局热键 | Carbon `RegisterEventHotKey` **不需要辅助功能权限**（`NSEvent.addGlobalMonitor` 才需要） |
| Services | `NSServices` 是数组，`INFOPLIST_KEY_*` 表达不了，必须改用真实 Info.plist |
| 剪贴板 | 没有变更通知，只能轮询 `changeCount`；密码管理器会打 `org.nspasteboard.ConcealedType` 标记，必须跳过 |
| 跑外部命令 | 管道读取必须放后台线程 —— 输出超过 64KB 时主线程 `waitUntilExit` 会与写端死锁 |
| 分段耗时 | `URLSessionTaskMetrics` 能给出 DNS / TCP / TLS / TTFB / 下载各段，比只报总时长有用得多 |

## 进度

- [x] **Phase 0** 骨架：四模板 + 命令面板（⌘K）+ MenuBarExtra + 4 个样板工具
- [x] **Phase 1** 编解码 ×10 —— Base64 / URL / Unicode / HTML 实体 / 字符串转义
      / JWT / 时间戳 / 进制 / UUID / 哈希
- [x] **Phase 2** 格式化 / 代码生成 ×9 —— JSON 工具箱 / JSON → 模型 / JSON Diff
      / 正则 / YAML 互转 / 命名转换 / 文本 Diff / Cron / Markdown 预览
- [x] **Phase 3** 样式与设计 ×12 —— 颜色转换 / 屏幕取色 / 调色板 / 对比度 / 缓动曲线
      / 阴影 / 渐变 / CSS→SwiftUI / 字号阶梯 / 单位换算 / 间距栅格 / 字体预览
- [x] **Phase 4** 图像与资源 ×9 —— 压缩/转换 / 图标切图套件 / EXIF / 图片⇄Base64
      / 二维码 / SVG / Lottie 检查（.icns 与 .ico 并入图标套件）
- [x] **Phase 5** 系统集成 ×8 —— 剪贴板监听 / 剪贴板历史 / Services 菜单 / 全局热键
      / 快捷指令动作 / CLI 伴生 / 拖放中枢 / 工具链
- [x] **Phase 6** 网络 ×6 —— HTTP 测试器 / 响应头分析 / WebSocket / IP 信息
      / DNS·Ping / 证书检查
- [x] **Phase 7** 打磨 —— 状态持久化 / 设置窗口（5 个 tab）/ 工具输入记忆
      / 工具隐藏与收藏排序 / 最近使用加权搜索 / 配置导出导入

路线图原定 54 个，实际 **52 个** —— Phase 4 把「图片压缩」和「格式转换」合并
（用的时候本来就是一起做的），`.icns` / `.ico` 并入图标套件（它们是多尺寸容器，
不是独立工具）。功能没减。

Phase 0 里刻意留给后续阶段的：全局 ⌥Space 唤起（需独立 `NSPanel` +
`RegisterEventHotKey`，Phase 5）、剪贴板 `changeCount` 轮询（Phase 5）、
每个工具的历史记录与输入持久化（Phase 7）、设置窗口（Phase 7）。
