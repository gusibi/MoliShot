# MoliShot

一个基于 Swift + AppKit + ScreenCaptureKit + Vision 的 macOS 截图工具，对标 Shottr Pro 的核心功能。

**⚠ 状态**：这是一个可用的基线版本，当前重点覆盖已经暴露在菜单栏和快捷键里的截图工作流。和成熟产品相比，仍有明显边界，尤其是滚动截图的稳定性和编辑器的轻量撤销能力。

## 已实现功能


| 模块       | 说明                                                                 |
| -------- | ------------------------------------------------------------------ |
| 区域截图     | 在当前鼠标所在显示器上进行区域选择，支持窗口 hover 高亮、放大镜、`pt`/`px` 实时尺寸、`Space` 移动选区、`Shift` 锁定比例、`Option` 中心缩放，避免把 overlay 画面带进最终结果 |
| 全屏截图     | 捕获当前鼠标所在显示器                                                        |
| 滚动截图     | Vision `VNTranslationalImageRegistrationRequest` 做帧间配准，手动滚动 + 拼接 |
| 标注编辑器    | 箭头、矩形、椭圆、直线、画笔、文字、自增编号、高亮、模糊、像素化、裁剪，支持缩放查看 / 实际尺寸 / 适配窗口 |
| OCR      | Vision 文字识别，自动检测语言，结果窗口支持查看与编辑，识别文本会复制到剪贴板                         |
| 屏幕取色器    | 系统 `NSColorSampler`，HEX 自动复制 + HUD 提示                              |
| 贴图 (Pin) | 浮动窗口置顶，hover 显示工具栏                                                 |
| 历史记录     | Application Support 目录持久化，网格浏览                                     |
| 全局快捷键    | 优先使用 `CGEventTap` 拦截截图热键；未授予辅助功能权限时自动降级到 HotKey，默认 ⇧⌘1 / ⇧⌘3 / ⇧⌘4 / ⇧⌘P / ⇧⌘R |
| 偏好设置     | 快捷键列表、屏幕录制/辅助功能权限状态、历史路径 |
| 导出分享     | 剪贴板、保存 PNG、上传到 0x0.st                                              |


## 构建

### 1. 安装 XcodeGen（首次）

```bash
brew install xcodegen
```

### 2. 生成 Xcode 项目

```bash
cd ~/Desktop/Shottr-Clone
xcodegen generate
open MoliShot.xcodeproj
```

### 3. 在 Xcode 中配置签名

首次打开后，在 Target `MoliShot` 的 **Signing & Capabilities** 面板：

- Team：选你自己的 Apple ID 或 "Sign to Run Locally"
- Bundle Identifier：可保留 `com.molishot.app` 或改成你自己的

### 4. 运行

`⌘R` 运行。第一次真正发起截图时，系统会按 `NSScreenCaptureUsageDescription` 弹出录屏授权：**System Settings → Privacy & Security → Screen Recording**（或「屏幕与系统音频录制」），勾选 `MoliShot` 后，**完全退出再打开**一次 App 最稳妥。

如果你希望截图热键触发时尽量保持目标 App 的菜单、Popover、tooltip 不被提前关闭，还需要授予 **Accessibility** 权限。没有该权限时截图仍可工作，但这部分行为只能尽力而为。

### 5. 打包成 DMG（自用）

仓库内置了一个自动打包脚本，会生成 `dist/MoliShot.dmg` 并自动打开输出目录：

```bash
cd ~/Desktop/Shottr-Clone
./scripts/build-dmg.sh
```

脚本会自动执行：

- `xcodegen generate`
- `Release` 构建
- 查找生成的 `MoliShot.app`
- 输出 `dist/MoliShot.dmg`
- 在 DMG 根目录放置 `MoliShot.app` 和 `Applications` 快捷入口，支持直接拖拽安装
- 打开 `dist/` 目录

### 录屏权限反复弹窗？

不要在启动时主动调用 `CGRequestScreenCaptureAccess()`：在从 Xcode 运行的 **Debug / 未签名** 构建里，`CGPreflightScreenCaptureAccess()` 有时会长期返回 `false`，于是每次启动都会再弹一次系统 sheet。当前版本已去掉该行为；若仍异常，请确认系统设置里勾选的是 **当前这条路径** 下的 `MoliShot`（例如 `DerivedData/.../Debug/MoliShot.app` 与 `/Applications/MoliShot.app` 会被系统当成不同条目）。正式发布后把 App 放进 `/Applications` 并固定签名即可。

### 遇到 `xcodebuild` 插件错误？

如果命令行 `xcodebuild` 报 `IDESimulatorFoundation` 加载失败，那是 Xcode 本身的系统组件需要初始化。先用 Xcode GUI 构建一次就能自动修复，或执行：

```bash
sudo xcodebuild -runFirstLaunch
```

这和本项目无关，是你本机 Xcode 安装状态问题。用 Xcode 图形界面直接打开 `.xcodeproj` 构建不受影响。

## 使用

启动后菜单栏会出现相机图标。默认快捷键：


| 动作            | 快捷键 |
| ------------- | --- |
| 区域截图          | ⇧⌘1 |
| 当前显示器截图  | ⇧⌘3 |
| 滚动截图          | ⇧⌘4 |
| 屏幕取色器      | ⇧⌘P |
| OCR 选区识别   | ⇧⌘R |


截图完成后会自动弹出编辑器窗口。工具栏左到右：Pin/复制 → 工具选择 → 颜色 + 粗细 → 裁剪/撤销/清空 → 缩放（放大 / 100% / Fit）→ OCR/保存/上传。

编辑器补充交互：

- 支持 `⌘+` / `⌘-` 缩放，`⌘0` 适配窗口，`⌘1` 实际尺寸
- 支持 `⌘C` 复制、`⌘S` 保存、`⌘Z` 撤销最后一个标注
- 文字标注支持双击重新编辑
- 状态栏会显示当前图片尺寸、标注数量、当前工具和缩放比例

## 项目结构

```
Sources/
├── App/                 # 应用入口、菜单栏、全局协调
├── Capture/             # ScreenCaptureKit、区域选择、滚动截图
├── Editor/              # 标注编辑器、各种 Annotation 类型
├── OCR/                 # Vision 文字识别
├── Pin/                 # 贴图浮动窗口
├── ColorPicker/         # 屏幕取色器
├── Ruler/               # 尺子 / 量角器
├── History/             # 历史记录存储和浏览
├── Hotkeys/             # 全局快捷键管理
├── Preferences/         # 偏好设置窗口
├── Services/            # 上传、导出服务
└── Utilities/           # 权限、扩展、辅助函数
Resources/
├── Info.plist
└── MoliShot.entitlements
project.yml              # XcodeGen 配置
```

## 已知限制和改进方向

1. **区域截图当前只在鼠标所在显示器启动**：这是当前实现的明确行为，不是跨所有显示器自由框选。
2. **编辑器撤销仍是轻量级模型**：当前支持取消当前操作或撤销最后一个标注，还没有完整 `NSUndoManager` / redo 栈。
3. **滚动截图仍依赖手动滚动**：当页面滚动过快、重叠区域过少或内容抖动明显时，拼接可能失败。
4. **OCR 仍是纯文本结果**：当前没有文字框高亮、逐块复制或结构化搜索。
5. **没有录屏**：当前版本只聚焦已经暴露出来的截图工作流。

## 依赖

- [HotKey](https://github.com/soffes/HotKey) — 全局快捷键，唯一的第三方依赖，由 SwiftPM 管理。

## 许可

自己决定，代码可自由修改。
