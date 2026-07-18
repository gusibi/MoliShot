# MoliShot UI 整改报告（设置页 + 编辑页）

> 生成日期：2026-07-18。基于 Apple 设计原则（Designing Fluid Interfaces / HIG）对现有代码的逐项审查。
> 每一项包含：现状（含文件:行号）、方案、组件选型（原生 or 自绘及理由）、实现要点、验收标准。
> 建议按文末的「执行顺序」分四批做，每批独立可验证、可提交。

## 总原则（贯穿所有条目）

1. **能用原生就用原生。** 系统组件免费获得：强调色跟随、暗色模式、Increase Contrast、
   辅助功能、未来 macOS 改版自动跟进。自绘只保留两处有充分理由的：`MoliHoverButton`
   （工具栏需要 selected/prominent 三态 + 即时 hover 反馈，原生 NSButton 做不到）和
   热键录制按钮（原生没有此控件）。
2. **单一设计源。** `MoliDesign`（Sources/Utilities/Extensions.swift）是唯一 token 来源。
   `PreferencesDesign`（PreferencesWindowController.swift:19-45）在设置页重构后应整体删除
   （Form 原生样式接管后 90% token 不再需要）。
3. **所有动画遵守现有的 `MoliDesign.reduceMotion` 开关**；新增动画一律先判断它。
4. 改完每一批跑一次类型检查（本机无 Xcode，用 swiftc -typecheck + 手编 HotKey module，
   见 AGENTS.md / 记忆），并在有 Xcode 的机器上过一遍验收标准。

---

# 第一部分：编辑页（EditorWindowController.swift + EditorView.swift）

## E1. 快捷键写进 tooltip（成本最低，先做）

**现状**：`toolShortcut` 表定义了 V/R/O/L/A/P/T/N/B/X/Y 单键切换
（EditorWindowController.swift:739-742），另有 Cmd+S/C/V/D/Z、Cmd+0/1/±、Cmd+[/] 等，
但所有按钮的 `toolTip` 只有名称，用户无从得知。

**方案**：tooltip 格式统一为 `"名称  快捷键"`，快捷键用 macOS 符号习惯（⌘⇧Z 而非 Cmd+Shift+Z）。

**实现要点**：
- `AnnotationTool` 增加 `var shortcutHint: String?`（返回 "V"、"R" 等，数据源就是
  `toolShortcut` 表——建议把表反转后挂到 AnnotationTool 上，避免两处维护）。
- `compactToolbarButton(title:symbol:action:)` 增加可选参数 `shortcut: String? = nil`，
  拼接 `button.toolTip = shortcut.map { "\(title)  \($0)" } ?? title`。
- 非工具按钮逐个补：保存 ⌘S、复制 ⌘C、撤销 ⌘Z、重做 ⇧⌘Z、放大 ⌘+、缩小 ⌘−、
  实际大小 ⌘1、适合窗口 ⌘0。
- `setAccessibilityLabel` 保持只有名称（读屏不需要念快捷键符号）。

**验收**：悬停矩形按钮显示「矩形  R」；悬停保存显示「保存  ⌘S」。

## E2. 工具栏视觉分组 + 「清空」挪位

**现状**：18 个控件一行平铺，仅靠 14pt 空隙分组（`toolbarGap()`，
EditorWindowController.swift:308-313）；破坏性的「清空」（trash）紧挨高频的撤销/重做
（:233-235）。

**方案**：
- 组间用**竖分隔线**替代部分空隙：工具组 | 样式组 | 历史组 …… 右侧输出组。
- 分隔线组件：不用 NSBox（默认样式偏重），自建一个 1pt 宽、16pt 高、
  `MoliDesign.hairline` 色的 NSView，包个工厂方法 `toolbarSeparator()`，两侧各留 8pt。
- 「清空」从历史组移除，放到右侧输出区（OCR 左边），并把 symbol 保持 trash、
  hover 时 `contentTintColor` 变 `NSColor.systemRed`（MoliHoverButton 加一个
  `isDestructive` 开关，复用现有 refreshStyle 流程）。不加确认弹窗——操作可撤销，
  弹窗反而违反 HIG（确认框只留给不可逆操作）。

**验收**：工具栏出现 3 条 hairline 分隔；清空按钮在 OCR 左侧，hover 变红；误点后 ⌘Z 可恢复。

## E3. 内联色板（编辑页体验提升最大的一项）

**现状**：描边色和填充色都是 `NSColorWell`（:17,24），每次改色要过系统取色面板，
对「红框标注」这种 95% 场景太重。

**方案**：预设色板一排小圆点 + 尾部保留 NSColorWell 作「自定义」入口。

**组件选型**：自绘 swatch 按钮（原生无此控件）。每个 swatch 是一个小 NSButton 子类
（或直接复用 MoliHoverButton 加圆形模式）：
- 直径 16pt，圆形，填充预设色；点击即 `editorView.setStrokeColor(_:)`。
- 选中态：外圈 2pt `NSColor.controlAccentColor` ring（`layer?.borderWidth/borderColor`），
  与当前生效色比对（sRGB 分量近似相等即视为选中）。
- 白色 swatch 加 1px hairline 描边防止融入背景。
- 预设 7 色：systemRed、systemOrange、systemYellow、systemGreen、systemBlue、black、white
  （全部 `.usingColorSpace(.sRGB)` 后存储，和现有 setFillColor 的做法一致）。
- 末位放缩小版 NSColorWell（28×24 保持现状）作自定义色；用户从面板选色后所有 swatch
  取消选中态。
- swatch 行放进现有 `toolBarStack` 样式组，替换当前 colorWell 的位置；
  `syncStyleControls(to:)`（:553-582）里同步选中 ring。
- 填充色（fillWell）**不做** swatch，保留 checkbox+colorWell——使用频率低，不值得占宽度。

**布局代价**：7 swatch × (16+4) + colorWell ≈ 170pt，比现在的单 colorWell 多 ~140pt。
配合 E7 的收纳机制解决（swatch 组的 visibility priority 设低，窄窗口时收进溢出面板）。

**验收**：点红色圆点立即变红且出现选中环；选中已有标注后点色板直接改该标注颜色；
色板与 colorWell 状态互斥正确。

## E4. 裁剪模式的常驻确认 UI

**现状**：进入裁剪只有一条 4 秒 toast 提示「回车应用/Esc 取消」（:449），
消失后界面上没有任何出口指示（wayfinding 缺失）。

**方案**：裁剪模式期间，画布底部中央悬浮一个确认条：`[✓ 应用]  [✕ 取消]`。

**组件选型**：`NSVisualEffectView`（material `.hudWindow`，圆角 10）+ 两个 MoliHoverButton，
✓ 用 `isProminent = true`（accent 填充），✕ 普通样式。与 MoliToast 同层但互斥
（进入裁剪时 `MoliToast.dismiss()`，改用此确认条替代 cropHint toast——保留 toast 只报
「已应用裁剪」结果）。

**实现要点**：
- 新建 `CropConfirmBar: NSView`（放 Editor/ 目录），由 EditorWindowController 持有；
  `editorViewDidChangeTool` 里根据 `editorView.cropMode` 显示/隐藏。
- 位置固定：`centerX == contentView.centerX`，`bottom == scrollView.bottom - 20`。
  不跟随裁剪框（跟随需要 zoom 坐标换算，且裁剪框频繁变动会抖，固定位置更稳）。
- 出现/消失动画：opacity 0→1 + scale 0.96→1，duration 0.18，遵守 reduceMotion。
- 按钮 action 直接调用现有 `applyCropModal()` / `cancelCropMode()`；键盘 Return/Esc
  路径（事件监视器里已实现）保持不变，两条路互为冗余。
- tooltip：「应用  ⏎」「取消  ⎋」。

**验收**：点裁剪按钮后确认条出现；画完选区点 ✓ 生效、点 ✕ 还原；回车/Esc 仍然可用；
退出裁剪模式确认条消失。

## E5. 缩小编辑窗口最小宽度 + 工具栏自适应收纳

**现状**：`window.minSize = 1080×420`（:48），`fitSize` 下限同样是 1080（:75）。
小截图（如 400×300）在 1:1 显示策略下会得到一个巨大空窗，观感是目前最差的一项。
1080 的唯一原因是塞下一整行工具栏。

**方案**：最小宽度降到 **720**；工具栏用 NSStackView 原生的
**visibility priority 收纳机制** + 溢出按钮。

**实现要点**：
- `toolBarStack.detachesHiddenViews = true`（NSStackView 原生行为，Apple 推荐做法，
  不要自己算宽度）。
- 分优先级：工具组按钮 + 保存/关闭 = `.mustHold`；撤销/重做/复制/Pin/OCR = 750；
  样式滑杆组（描边/不透明度/字号/效果）= 500；swatch 色板组（E3）= 400。
  窗口变窄时 NSStackView 自动按优先级从低到高隐藏。
- 加一个溢出按钮「…」（symbol `ellipsis`，常驻最右分组前）：点击弹 `NSPopover`
  （原生，behavior `.transient`），内容是一个纵向 NSStackView，装**当前被收纳**的
  控件的镜像。滑杆类控件不做镜像同步的复杂方案——直接把原控件 reparent 进 popover
  会破坏 stack 结构，推荐简单方案：popover 内重建同款滑杆，target 指向同一批
  `@objc` action（strokeChanged 等本来就读 sender.doubleValue，天然复用），
  打开 popover 时用 `syncStyleControls` 的同款逻辑刷一遍初值。
- 溢出按钮仅在有控件被收纳时显示：监听 `windowDidResize`，检查
  `toolBarStack.detachedViews.isEmpty`。
- `fitSize` 改为 `max(720, w+40)`；`minSize` 改 `720×420`。
- （顺带）`toolBarStack` leading 84pt 是给红绿灯留的 magic number（:126），
  改为读 `window.standardWindowButton(.zoomButton)` 的 frame 计算，防止未来系统改布局。

**验收**：窗口拖窄到 720 的过程中，先收 swatch、再收滑杆，工具按钮和保存始终可见；
「…」出现且 popover 内滑杆可用、值同步；小截图打开时窗口明显变小。

## E6. 编辑页微调打包

1. **底部缩放按钮触达面积**：`zoomBarButton` 从 24×20 → **28×22**（:354-355），
   symbol pointSize 11 不变（图标不用变大，热区要够）。
2. **Toast 材质化**：MoliToast（Extensions.swift:204-255）淡入时叠加
   `scale 0.96→1`（`layer` transform，锚点居中），淡出对称 1→0.97。
   duration 不变，reduceMotion 时保持纯 opacity。
3. **状态栏简化**：`updateStatusLabel`（EditorWindowController.swift:795-805）
   去掉 pt 段，只显 `1280×800 px · 3 个标注`。pt/px 双显是工程师视角，
   对用户唯一有意义的是导出像素。
4. **滑杆数值即时反馈**：拖动描边/字号/不透明度滑杆时用户看不到数值。
   最轻方案：拖动中把当前值打到滑杆自己的 `toolTip` 不可行（不实时弹出），
   改为拖动时在 zoomLabel 位置临时显示 `描边 4`（松手 0.8s 后恢复缩放百分比）；
   或者直接接受现状。**建议做**，一个 `showSliderValue(_ label: String)` 十行搞定。

## E7.（已知限制，本次不做，记录在案）

- 文字标注单行（NSTextField，回车即提交）。多行需换 NSTextView 方案，工作量大，
  独立立项。
- Pin/OCR/上传链路已验证可用，不动。

---

# 第二部分：设置页（PreferencesWindowController.swift 全量重构）

设置页的正确做法是**大规模删代码**：现有 ~900 行里约 450 行
（PreferencesDesign token、SettingsGroup/SettingsRow/SettingsStackedRow/
SettingsMessageRow/PreferenceActionButtonStyle/PreferenceTextFieldStyle/
PreferencePathValue/PermissionStatusLabel 的大部分）在手工模仿 macOS 13 系统设置的
外观。SwiftUI 原生 `Form` + `.formStyle(.grouped)` 就是那个外观，且永远和系统一致。

## S1. 骨架：NavigationSplitView 替换手写侧边栏

**现状**：手写 HStack + 自绘 sidebar（:125-207），不透明背景、无 hover 态、
选中样式自绘（accent 14% 底 + 2pt 竖条 + 描边，三层 overlay）。

**方案**（全原生）：

```swift
// PreferencesContentView 重写为：
NavigationSplitView {
    List(PreferencesPane.allCases, id: \.self, selection: $selectedPane) { pane in
        Label(pane.title, systemImage: pane.symbol)
    }
    .navigationSplitViewColumnWidth(196)
} detail: {
    Form {
        switch selectedPane { ... }   // 各 pane 只提供 Section 内容
    }
    .formStyle(.grouped)
}
```

- `List` 默认即 `.sidebar` 风格：半透明材质、原生 hover、原生选中高亮、
  跟随强调色，全部免费。删掉 `sidebarButton(for:)` 整个方法和三层 overlay。
- 窗口侧配合：`styleMask` 加 `.fullSizeContentView`；`titlebarAppearsTransparent`
  保持 true。侧边栏材质会自动延伸进标题栏区域（系统设置同款）。
- `selectedPane` 类型改 `PreferencesPane?`（List selection 要求 Optional），
  初值 `.general`。
- 窗口尺寸：宽度**固定 720**（系统设置就是固定宽度）：styleMask 去掉手工居中后
  用 `window.setContentSize` + 禁止横向 resize 的最简做法是保持
  `[.titled, .closable, .miniaturizable]` 不加 `.resizable`，同时**删除 minSize**
  （不可 resize 时 minSize 是死代码，现状 :64 就是这个问题）。
- 顶部 `padding(.top, 50)` 之类的标题栏补偿 hack 全部删除，
  NavigationSplitView 自己处理安全区。

**验收**：侧边栏半透明（后面桌面透过来）；行 hover 有高亮；选中样式与系统设置一致；
切换语言后仍正常（languageDidChange 重建 rootView 的机制保留）。

## S2. 内容区：全部换成 Form 原生组件

**组件替换对照表**（这是报告的核心，逐行执行）：

| 现有自制组件 | 替换为 | 说明 |
| --- | --- | --- |
| `SettingsGroup { }` | `Section { }` | grouped Form 自带圆角卡片+分隔线 |
| `SectionHeader(title:)` | `Section("标题") { }` 的 header | 原生小灰字，删组件 |
| `SettingsRow(label:){控件}` | `LabeledContent("标签") { 控件 }` 或控件自带 label | 原生行高/对齐 |
| `SettingsStackedRow` | `VStack` 放在 Section 内一行，或 `LabeledContent` + `.labeledContentStyle` | 大多数场景 LabeledContent 够用 |
| `SettingsMessageRow` | Section 的 `footer:` | 说明文字的原生位置就是 footer |
| `PreferenceActionButtonStyle` | 删除，用标准 `Button` + `.buttonStyle(.bordered)` | 原生按压态/强调色 |
| `PreferenceTextFieldStyle` | 删除，用 `TextField` + `.textFieldStyle(.roundedBorder)` + `.frame(width: 64)` | |
| `PreferencePathValue` | `Text(path).truncationMode(.middle).foregroundStyle(.secondary)` 放 LabeledContent value 位 | 不需要自绘底框 |
| `PermissionStatusLabel` | 保留概念，简化实现：`Label("已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green)`，去掉自绘胶囊底/描边 | 状态用色+图标表达即可，胶囊是多余的一层 |
| `PaneHeader` | **整体删除** | 见 S3 |
| `PreferencesDesign` enum | **整体删除** | Form 接管所有外观 |

**具体控件写法**：

```swift
// General pane 示例（目标形态）：
Section {
    Picker(L10n.text(.language), selection: $languageRaw) { ... }   // label 不再 hidden
    Toggle(L10n.text(.autoStart), isOn: $launchesAtLogin)
}

Section {
    LabeledContent(L10n.text(.screenRecordingPermission)) {
        HStack {
            permissionBadge(granted: hasScreenCapturePermission)
            Button(L10n.text(.openScreenRecordingSettings)) { ... }
        }
    }
} header: {
    Text(L10n.text(.permissions))          // 新增一个"权限"节标题，见 S3
} footer: {
    Text(L10n.text(.accessibilityPermissionHint))   // 原 SettingsMessageRow
}
```

- Picker/Toggle **不再 labelsHidden**：Form 里控件自带 label 就是行标签，
  删掉外层包装，这正是行去重的来源。
- 存储页的 JPEG 质量条件行：

```swift
if saveFormat == .jpeg {
    Slider(value: $jpegQuality, in: range) { Text(L10n.text(.jpegQuality)) }
}
// Section 上加：.animation(.default, value: saveFormat)   ← 修掉瞬间跳变（原 S10）
```

- 历史数量行现在 TextField 和 Stepper 各挂一份重复的 onChange clamp 逻辑
  （:865-883），合并为一个私有方法 `applyHistoryLimit(_:)` 两处调用，
  或直接换成带内建 TextField 的写法：
  `Stepper(value: $historyLimit, in: min...max) { TextField(...) }`。

**验收**：三个 pane 外观与系统设置（如"通用"）目测一致；暗色模式正确；
强调色改成绿色后按钮/选中/Toggle 全部跟随；文件行数净减 ≥ 350 行。

## S3. 信息层次去重

执行三个删除（配合 S2 做）：

1. **PaneHeader 整体删除**：eyebrow 行（icon + "偏好设置"小字）+ 24pt 大标题。
   "偏好设置"已在窗口标题/侧边栏出现，pane 大标题由
   `.navigationTitle(selectedPane.title)` 提供（NavigationSplitView detail 区
   原生标题位置）。
2. **"屏幕录制权限"双写**（:539+:542）：SectionHeader 与行 label 同字符串。
   重构后 Section header 用「权限」（新 L10n key `permissions`，中/英都要加），
   行 label 用「屏幕录制」/「辅助功能」（新 key 或复用现有），
   value 位放状态+按钮。同一个词在一屏内最多出现一次。
3. **侧边栏顶部 app icon + "偏好设置" 标题行删除**（:139-151）：
   NavigationSplitView 的窗口标题承担此职责。

## S4. 热键录制按钮（保留自绘，小修）

`HotkeyRecorderButton` 是合理的自绘（原生无此控件），保留架构，只改三点：

1. tooltip 补操作说明：`"点击后按下新快捷键；⎋ 取消，⌫ 清除"`。
2. 录制态增加脉冲反馈：border 常亮 accent 之外，可选加
   `NSAnimation` 让 border alpha 0.5↔1 呼吸（1.2s 周期），reduceMotion 时不呼吸。
   低优先级，可跳过。
3. token 引用从 `PreferencesDesign.*` 改为 `MoliDesign.*`（PreferencesDesign 已删）。

## S5. 权限状态自动刷新（现状已可，确认不回退）

现有 `didBecomeActiveNotification` 刷新机制（:583）保留——用户去系统设置授权后
切回 app 即刷新，这是正确行为，重构时别丢。

---

# 执行顺序（四批，每批独立提交）

| 批次 | 内容 | 预估规模 |
| --- | --- | --- |
| ① 速赢 | E1 快捷键 tooltip、E2 工具栏分组+清空挪位、E6 全部微调、S4.1 热键 tooltip | 小，半天 |
| ② 设置页重构 | S1 + S2 + S3 + S4.3（一起做，互相依赖；净删代码） | 中 |
| ③ 编辑页交互 | E3 内联色板、E4 裁剪确认条 | 中 |
| ④ 工具栏收纳 | E5（依赖 E3 完成后再定优先级分配） | 中偏大 |

## 全局验收清单（每批完成后过一遍）

- [ ] 亮/暗模式切换（含运行中切换），无 cgColor 残留旧色（自绘 layer 色都要走
      `viewDidChangeEffectiveAppearance` 刷新——MoliHoverButton 已有此模式，新组件照抄）
- [ ] 系统强调色改变后全部跟随
- [ ] 系统设置开启「减弱动态效果」后：无 scale/spring，仅淡入淡出
- [ ] 中/英语言切换（运行中触发 `.appLanguageDidChange`）后所有新增文案正确
- [ ] 新增 L10n key（permissions 等）中英双语都已补
- [ ] 键盘全链路：工具单键、⌘ 系列、裁剪 ⏎/⎋、删除键——在点击过任意工具栏控件后仍有效
- [ ] `swiftc -typecheck` 通过（xcodegen 项目，新增文件需重跑 `xcodegen generate`）
