# MoliShot

[English](README.md) | 中文版

一个基于 Swift + AppKit + ScreenCaptureKit + Vision 的 macOS 截图工具，对标 Shottr Pro 的核心功能。

**当前版本**：v0.7.1 — 界面与交互整改（原生 SwiftUI 设置页、编辑器色板、裁剪确认条、响应式工具栏）。

**⚠ 状态**：可用基线版本，覆盖菜单栏与快捷键里的完整截图工作流。和成熟产品相比仍有边界，主要是滚动截图稳定性与 OCR 结构化输出。

## 已实现功能


| 模块       | 说明                                                                 |
| -------- | ------------------------------------------------------------------ |
| 区域截图     | 在当前鼠标所在显示器上进行区域选择，支持窗口 hover 高亮、放大镜、`pt`/`px` 实时尺寸、`Space` 移动选区、`Shift` 锁定比例、`Option` 中心缩放，避免把 overlay 画面带进最终结果 |
| 全屏截图     | 捕获当前鼠标所在显示器                                                        |
| 滚动截图     | Vision `VNTranslationalImageRegistrationRequest` 做帧间配准，手动滚动 + 拼接 |
| 标注编辑器    | 箭头、矩形、椭圆、直线、画笔、文字、自增编号、高亮、模糊、像素化、裁剪。真实撤销/重做、选中改样式（颜色/描边/字号/不透明度/填充色）、8-handle resize、复制粘贴重复、Z 序、可调模糊半径、PNG/JPEG 导出 |
| OCR      | Vision 文字识别，自动检测语言，结果窗口支持查看与编辑，识别文本会复制到剪贴板                         |
| 屏幕取色器    | 系统 `NSColorSampler`，HEX 自动复制 + HUD 提示                              |
| 贴图 (Pin) | 浮动窗口置顶，hover 显示工具栏                                                 |
| 历史记录     | Application Support 目录持久化，网格浏览                                     |
| 全局快捷键    | 优先使用 `CGEventTap` 拦截截图热键；未授予辅助功能权限时自动降级到 HotKey，默认 ⇧⌘1 / ⇧⌘3 / ⇧⌘4 / ⇧⌘P / ⇧⌘R |
| 偏好设置     | 快捷键列表、屏幕录制/辅助功能权限状态、历史路径 |
| 导出分享     | 剪贴板、保存 PNG/JPEG、上传到 0x0.st                                              |


## 下载与安装

### 下载

从 [GitHub Releases](https://github.com/gusibi/MoliShot/releases) 下载最新 `MoliShot-vX.Y.Z.dmg`，拖入 `/Applications` 即可。

### DMG 未签名，首次打开被拦截怎么办

MoliShot 的 DMG **没有开发者签名**（Gatekeeper 不会自动放行）。双击打开 App 时，macOS 可能弹出以下任一拦截：

- **"MoliShot 无法打开，因为它来自身份不明的开发者"**
- **"MoliShot 已损坏，无法打开"**（部分 macOS 版本对未签名 App 的误导性提示）

任选一种方式放行：

**方式 A：右键打开（最简单）**

1. 在 Finder 里定位到 `MoliShot.app`
2. **按住 Control 键点击**（或右键）App 图标，选「打开」
3. 弹窗里点「打开」确认

**方式 B：系统设置放行**

1. 双击 App 触发拦截弹窗后，关闭弹窗
2. 打开 **系统设置 → 隐私与安全性**
3. 滚动到底部，找到关于 "MoliShot" 的提示，点「仍要打开」
4. 之后再双击 App 即可打开

**方式 C：命令行移除隔离属性**（适合"已损坏"提示）

```bash
xattr -dr com.apple.quarantine /Applications/MoliShot.app
```

执行后双击 App 即可。这是 macOS 对未签名下载文件的隔离标记，移除不影响功能。

> 放行后系统会记住该 App，后续打开不再拦截。录屏权限和辅助功能权限需在系统设置里单独授予（见下文「使用」）。

## 构建

### 1. 安装 XcodeGen（首次）

```bash
brew install xcodegen
```

### 2. 生成 Xcode 项目

```bash
cd /path/to/MoliShot
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


截图完成后会自动弹出编辑器窗口。工具栏左到右：Pin/复制 → 工具选择 → 颜色/描边/字号/不透明度/填充/模糊半径（按选中类型条件显示）→ 裁剪/撤销/重做/清空 → 缩放 → OCR/保存/上传。

编辑器快捷键：

| 动作 | 快捷键 |
| --- | --- |
| 撤销 / 重做 | `⌘Z` / `⌘⇧Z` |
| 复制选中标注（无选中时复制整图） | `⌘C` |
| 粘贴标注 | `⌘V` |
| 重复标注 | `⌘D` |
| 删除选中 | `Delete` / `⌫` |
| 上移/下移/置顶/置底 Z 序 | `⌘]` / `⌘[` / `⌘⇧]` / `⌘⇧[` |
| 应用裁剪 / 取消裁剪 | `Enter` / `Esc` |
| 缩放 / 适配窗口 / 实际尺寸 | `⌘+` `⌘-` / `⌘0` / `⌘1` |
| 保存 | `⌘S` |
| 取消选中 / 退出当前交互 | `Esc` |

工具单键切换（文字编辑态自动透传输入）：`V` 选择 / `R` 矩形 / `O` 椭圆 / `L` 直线 / `A` 箭头 / `P` 画笔 / `T` 文字 / `N` 编号 / `B` 模糊 / `X` 像素化 / `Y` 高亮。

编辑器补充交互：

- 选中标注后调颜色/描边/字号/不透明度/填充色/模糊半径 → 即时生效且可撤销
- 选中标注拖 handle 可 resize（线条/箭头拖端点，文字 resize 缩放字号）
- 文字标注支持双击重新编辑
- 状态栏显示当前图片尺寸、标注数量、当前工具和缩放比例

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
2. **滚动截图仍依赖手动滚动**：当页面滚动过快、重叠区域过少或内容抖动明显时，拼接可能失败。
3. **OCR 仍是纯文本结果**：当前没有文字框高亮、逐块复制或结构化搜索。
4. **DMG 未签名**：首次打开需手动放行（见上方「下载与安装」）。后续可考虑接入 Developer ID 签名 + 公证。
5. **没有录屏**：当前版本只聚焦已经暴露出来的截图工作流。
6. **性能优化未完全到位**：模糊/像素化已做渲染缓存，但底图每帧栅格化与 zoom 降采样尚未实现，4K + 大量标注时拖拽可能不够流畅。

## 依赖

- [HotKey](https://github.com/soffes/HotKey) — 全局快捷键，唯一的第三方依赖，由 SwiftPM 管理。

## 许可

自己决定，代码可自由修改。
