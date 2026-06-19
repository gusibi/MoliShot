# 截图编辑窗口重构 PRD

> 上游访谈：`/grill-with-docs`（grilling skill, 2026-06-19），共 19 项决策点已与用户逐项确认。
> 下游：`/to-issues` 据此拆分为可独立认领的工单。

## 目标

修复 MoliShot 截图编辑窗口的核心可用性问题（撤销不可靠、选中无法改样式、resize 缺失、裁剪 UX 混乱），并补齐 P2 增强能力（不透明度、填充色、保存格式、模糊半径、复制粘贴、Z 序）。同时伴随性解耦 `EditorView`/`EditorWindowController`，抽出纯逻辑组件以支撑后续迭代与测试。

## 非目标

- 不做"可回溯编辑文档"（保存 .molishot bundle / json 旁路）。序列化能力仅用于剪贴板（Q9）。
- 不做多选、群组、锁定、对齐、吸附、箭头样式（Q15、Q10）。
- 不重构 OCR/上传/钉图/历史等外部动作（Q18）。
- 不引入 MVVM 全面分层（Q13）。

## 现状问题（基线）

| 问题 | 位置 |
|---|---|
| Undo 非真实历史，仅丢最后一条标注/取消编辑 | `EditorView.swift:227-245` |
| 无 Redo | `EditorWindowController.swift:189`（按钮无模型） |
| 颜色/描边控件只作用于新建，选中项改不动 | `EditorWindowController.swift:298-304` |
| 字号字段存在但无 UI 入口，文字写死 semibold | `EditorView.swift:32`, `Annotations.swift:222-226` |
| 无 resize handle，仅整体移动 | `EditorView.swift:127-130` |
| hit-test 用粗略包围盒，线条/画笔空白处也命中 | `Annotations.swift:77-79,174-176` |
| 裁剪既是工具又是 toolbar 按钮，同图标同标题；无框时应用按钮静默无效 | `EditorWindowController.swift:165-170,188,308-312` |
| 标注导出直接拍平，不可序列化 | `EditorView.swift:281-323` |
| `Annotation` 用 class + 空方法重写模拟抽象基类 | `Annotations.swift:43-54` |
| `EditorView`/`EditorWindowController` 各 445/533 行强耦合 | — |

## 设计决策（19 项，均已确认）

### D1 范围：P0 + P1 + P2（含伴随性架构解耦）

P0=修复回归性 bug；P1=体验硬伤；P2=增强。架构重构不单独立项，在实现过程中顺手做必要解耦。

### D2 数据模型：值类型 struct + protocol

`Annotation` 改为 protocol，各标注类型为 `struct`。`[Annotation]` 拷贝语义天然支持 undo 快照、resize/改样式生成新 struct 替换。

```swift
protocol Annotation {
    var id: UUID { get }
    var bounds: CGRect { get }
    var style: AnnotationStyle { get set }
    func hitTest(_ point: CGPoint) -> Bool           // 底图坐标
    func resized(to newBounds: CGRect) -> Self
    func rendered(in context: CGContext)             // 或返回 NSImage
}
```

### D3 撤销/重做：全状态快照栈

`HistoryStack<EditorState>`，每次原子操作前 push 当前 state，redo 栈在新操作时清空。

```swift
struct EditorState: Equatable {
    var annotations: [Annotation]
    var cropRect: CGRect?
    var selection: UUID?
}
```

### D4 标识：每条标注带 `id: UUID`

创建时生成，拷贝保留。选中态存 `UUID?` 跨快照追踪。复制粘贴生成新 UUID 避免冲突。

### D5 控件双重作用 + 统一 `AnnotationStyle`

无选中时设默认值，有选中时改选中项并 push 一次快照。

```swift
struct AnnotationStyle: Codable, Equatable {
    var color: NSColor
    var strokeWidth: CGFloat
    var fontSize: CGFloat
    var opacity: CGFloat          // 0...1, D10
    var fillColor: NSColor?       // nil=透明, D10
}
```

模糊/像素化的 `radius`/`pixelSize` 作为该标注 struct 的专属字段（不入通用 Style）。

### D6 resize：统一 8 handle（四角+四边）bbox 缩放

矩形/椭圆/文字/序号/模糊按 bbox 缩放；线条/箭头特化为两端 handle（2 个）；画笔 resize 时对整条 path 做 affine 变换。约束最小尺寸防负数。

### D7 hit-test：分类型就近

形状类用 bounds/填充区域；线条/箭头/画笔用"点到线段距离 < 阈值 6pt × backingScaleFactor"；文字用 text rect。点空白不选中。

### D8 裁剪：模态流程 + 移出工具列表 + cropRect 作渲染 clip 不破坏底图

点 toolbar"裁剪"进入模态（光标十字、拖拽裁剪框、可调框边/角/移动、框外半透明遮罩预览）。Enter 应用 / Esc 取消 / 再次点按钮退出。移除工具列表里的 crop 工具。无框时按钮禁用。`baseImage` 始终保留全图，cropRect 仅渲染 clip + 导出截取，撤销零成本（清 cropRect）。

### D9 复制/粘贴/重复：应用内 Cmd+C/V + Cmd+D

序列化到自定义 UTI `com.eztolab.molishot.annotations`（Codable）+ PNG 兜底。Cmd+V 反序列化生成新 UUID 粘贴到原位置偏移 +10pt。跨 MoliShot 编辑窗口可用。粘贴时只处理自定义 UTI，图像粘贴走"导入底图"另一路径（不在本次范围）。

### D10 P2 控件增项：做 1/2/3/4，不做 5（箭头样式）

1. 不透明度滑块 0–100% → `AnnotationStyle.opacity`
2. 填充色（矩形/椭圆/高亮，`fillColor: NSColor?`，nil 默认透明）+ 启用开关
3. 保存格式选择：PNG（默认无损）/ JPEG（质量滑块 0.3–1.0，默认 0.85）
4. 模糊半径/像素块大小专属滑块，仅选中该类标注时显示

控件区条件显示：颜色井 | 填充色井(条件) | 描边滑块 | 字号(条件) | 不透明度滑块 | 模糊半径(条件)。

### D11 快捷键

**工具切换**（单键，文字编辑态透传给 NSTextField）：`V` 选择 / `R` 矩形 / `O` 椭圆 / `L` 直线 / `A` 箭头 / `P` 画笔 / `T` 文字 / `N` 序号 / `B` 模糊 / `X` 像素化 / `Y` 高亮（避开 Cmd+H）。

**编辑**：`Cmd+Z` 撤销 / `Cmd+Shift+Z` 重做 / `Cmd+C/V` 复制粘贴 / `Cmd+D` 重复 / `Delete`/`Backspace` 删除 / `Esc` 取消选中或退出裁剪模态 / `Enter` 应用裁剪 / `Cmd+]` `[` 上移/下移 Z 序 / `Cmd+Shift+]` `[` 置顶/置底。

**视图**：`Cmd+0` 适配窗口 / `Cmd+=`/`Cmd+-` 缩放 / `Cmd+1` 100%。

### D12 不做可回溯编辑；导出 PNG + JPEG

不做 .molishot bundle / json 旁路。导出格式仅 PNG + JPEG，不加 WebP/HEIC。

### D13 架构解耦：最小拆分 3 类型 + XCTest

抽出：
- `HistoryStack<T>` — 泛型快照栈，undo/redo/push/canUndo/canRedo。
- `AnnotationRenderer` — `func render(annotations:, cropRect:, baseImage:, zoom:) -> NSImage`，纯函数式，导出与画布共用。
- `AnnotationHitTester` — `func hitTest(point:, annotations:, zoom:) -> UUID?` + handle 检测。

`EditorView` 变"输入编排器"：mouseDown → hitTest → 选工具/选中/画框 → 修改 state → HistoryStack.push → 触发重绘。`EditorWindowController` 只管窗口/工具栏/快捷键/外部动作。

为上述 3 类型新增 XCTest：命中阈值、handle 检测、undo/redo 边界、序列化往返。

### D14 文字编辑：commit 入栈一次；resize 缩放字号

编辑期间不入栈，commit（回车/失焦）时若内容变化 push 一次；Cancel 不 push。文字 resize = 字号按 bbox 高度比例缩放，bbox 宽高由字号+行数决定。

### D15 仅做 Z 序，不做多选/锁定/对齐/群组/吸附

选中态维持单选 `UUID?`。Z 序靠重排 `annotations` 数组顺序实现。吸附不做。

### D16 导出按底图原始像素；cropRect 底图坐标；序号不自动重排

坐标体系统一为"底图真实像素坐标系"（与 commit `da56742` 修复一致）。zoom 只影响屏幕显示。Renderer 输入底图像素+标注（底图坐标）+cropRect，输出底图像素图。删除中间序号后保持稳定标识（#1/#3），不自动重排。

### D17 性能：分层缓存 + 模糊按需栅格化 + zoom 降采样

底图静态 backing bitmap 只渲染一次缓存；标注画到透明 overlay 层每帧重绘；模糊/像素化 CI 结果按 annotation ID 缓存，bounds/参数变化时失效。zoom > 1 时底图降采样显示。`AnnotationRenderer` 分 `baseLayer`（缓存）+ `overlay`（每帧）。

### D18 不动外部动作；钉图/导出/复制共用 Renderer 验收

OCR/上传/钉图/历史保持现状。钉图调用 EditorView 导出方法，验证用真实像素（共享 AnnotationRenderer）。

### D19 实施顺序：4 里程碑串行 + 验收模板

```
M1 基础设施（内部重构，行为不变）
  └→ M2 P0 编辑核心（撤销/重做 + 选中改样式 + 文字入栈）
       └→ M3 P1 体验硬伤（resize + 就近命中 + 裁剪模态 + Z 序）
            └→ M4 P2 增强 + 收尾（控件 + 复制粘贴 + 快捷键 + 性能 + 钉图验收）
```

**验收模板**（每个 issue）：行为变更描述 / 涉及文件 / 单测覆盖（M1 必须，M2-M4 尽量）/ 手动验证清单（截图→操作→预期）/ 回归检查。

---

## 里程碑拆分

### M1 基础设施（内部重构，对外行为不变）

**目标**：把可变 class 标注体系换成 struct+protocol+UUID+Style，抽出 HistoryStack/Renderer/HitTester 三个纯逻辑类型并配单测。完成后编辑器对外行为与现状完全一致，但底层已可支撑后续功能。

**范围**：
- 重构 `Annotations.swift`：`Annotation` protocol + 各 struct（Arrow/Rectangle/Ellipse/Line/Pen/Text/Number/Blur/Pixelate/Highlight），每条带 `id: UUID` + `style: AnnotationStyle`。
- 新增 `HistoryStack<T>`（Sources/Editor/HistoryStack.swift）。
- 新增 `AnnotationRenderer`（Sources/Editor/AnnotationRenderer.swift），抽取 `EditorView` 现有渲染逻辑为纯函数。
- 新增 `AnnotationHitTester`（Sources/Editor/AnnotationHitTester.swift），抽取现有命中逻辑（暂用粗略 bounds，M3 再升级就近）。
- `EditorView`/`EditorWindowController` 改为调用上述类型，行为不变。
- 新增 XCTest：`HistoryStackTests`、`AnnotationRendererTests`、`AnnotationHitTesterTests`、`AnnotationCodableTests`（序列化往返）。

**验收**：手动截图→所有现有工具（箭头/矩形/椭圆/直线/画笔/文字/序号/模糊/像素化/高亮/裁剪）行为与重构前一致；单测全绿。

**不做**：真撤销栈接入（M2）、resize、就近命中、模态裁剪、新控件。

### M2 P0 编辑核心

**目标**：解决最痛的两类回归——撤销不可靠、选中无法改样式。

**范围**：
- `EditorView` 接入 `HistoryStack`：所有原子操作（新建/移动/删除/改样式/文字 commit/裁剪应用）前 push 当前 state。现状"丢最后一条"逻辑移除。
- Redo 栈：新操作清空 redo；`Cmd+Shift+Z` 弹 redo。
- 颜色井 / 描边滑块双重作用（D5）：无选中设默认 Style，有选中改选中项 style 并 push。
- 新增字号控件（D5）：文字类选中时显示，双重作用。
- 文字编辑 commit 入栈一次（D14）。

**验收**：手动验证撤销/重做跨移动/删除/改色/改字/裁剪均正确；选中矩形改色即时生效；新建矩形用上次颜色。

**不做**：resize、就近命中、模态裁剪、P2 控件、复制粘贴、Z 序、快捷键表、性能优化。

### M3 P1 体验硬伤

**目标**：解决 resize 缺失、命中不准、裁剪 UX 混乱、Z 序无法调整。

**范围**：
- `AnnotationHitTester` 升级为分类型就近（D7）：线条/箭头/画笔用点到线段距离阈值 6pt × backingScaleFactor。
- resize handle（D6）：选中时画 8 handle（线条/箭头特化两端），拖拽生成 resized struct 替换并入栈。文字 resize 缩放字号（D14）。
- 裁剪模态重构（D8）：移出工具列表，进入模态流程，半透明遮罩预览，Enter/Esc/再点按钮控制，无框禁用，cropRect 作渲染 clip 不破坏底图。
- Z 序（D15）：`Cmd+]`/`[`/`Cmd+Shift+]`/`[` 重排 annotations 数组。

**验收**：线条空白处点不选中；选中矩形拖角缩放；裁剪模态可预览可取消可撤销；Z 序调整后遮挡关系变化。

**不做**：P2 控件、复制粘贴、快捷键全表、性能优化、钉图验收。

### M4 P2 增强 + 收尾

**目标**：补齐增强能力、统一快捷键、性能优化、钉图链路验收。

**范围**：
- 控件增项（D10）：不透明度滑块、填充色井+开关（矩形/椭圆/高亮）、模糊半径/像素块大小滑块（条件显示）、保存格式选择（PNG/JPEG + 质量滑块）。
- 复制/粘贴/重复（D9）：自定义 UTI `com.eztolab.molishot.annotations` + PNG 兜底，偏移 +10pt。
- 快捷键全表（D11）：工具单键切换（文字编辑态透传）+ 编辑键 + 视图键，高亮用 `Y`，重做 `Cmd+Shift+Z`。
- 性能（D17）：`AnnotationRenderer` 分 baseLayer 缓存 + overlay 每帧；模糊按 annotation ID 缓存；zoom 降采样。
- 钉图/导出/复制共用 Renderer 验收（D18）：确认钉图用真实像素，无 Retina 回归。

**验收**：不透明度/填充色/模糊半径可调且撤销正确；Cmd+C/V/D 跨窗口工作；快捷键无冲突；4K 底图+多模糊拖拽流畅；钉图清晰。

---

## 文件结构（最终态）

```
Sources/Editor/
  Annotations.swift            # protocol + 各 struct（重构后）
  AnnotationStyle.swift        # 统一样式 struct（Codable）
  HistoryStack.swift           # 泛型快照栈（新）
  AnnotationRenderer.swift     # 纯函数渲染，导出/画布共用（新）
  AnnotationHitTester.swift    # 命中 + handle 检测（新）
  EditorView.swift             # 输入编排器（瘦身后）
  EditorWindowController.swift # 窗口/工具栏/快捷键/外部动作（瘦身后）

Tests/EditorTests/             # 新增测试 target（若不存在）
  HistoryStackTests.swift
  AnnotationRendererTests.swift
  AnnotationHitTesterTests.swift
  AnnotationCodableTests.swift
```

## 全局约束

- 平台：macOS（Swift/AppKit），保持现有部署目标版本。
- 保留 commit `da56742` 的 Retina 真实像素修复，导出链路不得回归。
- 不引入新第三方依赖（CoreImage 已够用）。
- 遵循现有代码风格（中文注释允许，与现状一致）。
- 每个里程碑可独立合并、验证、回滚。

## 自检

- [x] D1-D19 每项决策均有对应里程碑任务
- [x] 4 里程碑依赖顺序明确（M1→M2→M3→M4）
- [x] 非目标边界清晰（不做回溯编辑/多选/外部动作重构/MVVM）
- [x] 验收模板覆盖每个里程碑
- [x] 与 Retina 修复（`da56742`）的坐标体系一致（D16）
