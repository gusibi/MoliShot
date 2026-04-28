以下是面向 macOS Swift 截图工具的完整设计方案，聚焦于"如何不踩坑"。

***

# macOS Swift 截图工具完整设计方案

## 核心原则

截图工具的覆盖层窗口必须满足三个基本约束：
1. **不抢夺焦点** — 不改变系统 active app
2. **不发送鼠标事件给底层窗口** — 不触发 hover/exit
3. **截图时机正确** — 在覆盖层出现之前先采集屏幕内容

***

## 一、覆盖层窗口配置（最核心）

### 使用 NSPanel + nonActivatingPanel

这是最关键的一步。普通 `NSWindow` 创建时会自动 become key window，抢走焦点导致菜单消失。必须用 `NSPanel`：

```swift
class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSScreen.main!.frame,
            styleMask: [
                .borderless,
                .nonactivatingPanel   // ⚠️ 关键：不激活 app
            ],
            backing: .buffered,
            defer: false
        )

        // 不成为 key window（保留原 app 的 first responder）
        self.becomesKeyOnlyIfNeeded = true

        // 浮在所有窗口之上，包括菜单
        self.level = .screenSaver       // 或 .popUpMenu（比菜单栏更高）

        // 忽略鼠标事件穿透策略由 contentView 控制，这里先关闭
        self.ignoresMouseEvents = false

        // 不出现在截图、Exposé、Mission Control 中
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle             // 不参与 Cmd+` 切换
        ]

        // 覆盖层本身不出现在截图结果里
        self.sharingType = .none

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
    }

    // 拒绝成为 key window（即使点击也不抢焦点）
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

> **踩坑记录**：`styleMask` 必须在 `init` 时设置，运行时修改 `nonactivatingPanel` 无效 。 [developer.apple](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)

***

### Window Level 选择

| 场景 | 推荐 Level |
|---|---|
| 普通截图覆盖层 | `.screenSaver` |
| 需要覆盖系统菜单栏 | `.popUpMenu + 1` |
| 取色器等工具层 | `.floating` |
| 需要低于系统弹窗（权限弹窗）| `.screenSaver`（系统弹窗在更高层） |

```swift
// 覆盖菜单栏本身
panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
```

***

## 二、鼠标事件处理（避免触发 hover）

### 覆盖层 contentView 的命中测试

覆盖层收到鼠标事件后，底层窗口不应再收到任何 `mouseEntered`/`mouseMoved`/`mouseExited`。关键是正确处理 `hitTest`：

```swift
class OverlayView: NSView {
    // 覆盖层吃掉所有事件，不穿透给底层
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self   // 返回 self 表示自己处理，不穿透
    }

    // 阻止鼠标移动事件传递给底层
    override func mouseMoved(with event: NSEvent) {
        // 只在这里处理，不调用 super（不传播）
        updateCrosshair(event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        // 吞掉，不传给 nextResponder
    }

    override func mouseExited(with event: NSEvent) {
        // 吞掉
    }
}
```

### 使用 CGEventTap 拦截全局鼠标事件（可选增强）

如果覆盖层还不够，可以在系统层拦截鼠标事件：

```swift
// 仅监听，不修改事件（passive tap）
let eventMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)

let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,        // ⚠️ listenOnly = 不阻断事件
    eventsOfInterest: eventMask,
    callback: { _, _, event, _ in return Unmanaged.passRetained(event) },
    userInfo: nil
)
```

> **踩坑记录**：若用 `.defaultTap`（非 listenOnly），修改或丢弃事件需要 Accessibility 权限，且会引起用户警觉 。截图工具仅需监听坐标，用 `listenOnly` 即可。 [github](https://github.com/usagimaru/EventTapper)

### 全局鼠标监听（不需要权限）

```swift
// 监听全局鼠标移动，用于取色、坐标显示等
NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
    // 注意：addGlobalMonitor 收到的事件是只读的，不影响底层
    self.updateMagnifier(at: NSEvent.mouseLocation)
}
```

> **踩坑记录**：`addGlobalMonitorForEvents` 不能拦截事件，只能观察，这正是截图工具需要的 。 [reddit](https://www.reddit.com/r/swift/comments/1pyohmy/why_does_nseventaddglobalmonitorforevents_still/)

***

## 三、截图时机：先采集，后显示

**最大的坑**：很多开发者先显示覆盖层，再截图，导致：
- 覆盖层触发目标 app 的 `resignActive`，菜单关闭
- 截图内容里包含覆盖层 UI 本身

正确流程：

```swift
func activateScreenshot() {
    // ① 先采集当前屏幕内容（覆盖层还没出现）
    let snapshot = captureCurrentScreen()

    // ② 将快照作为背景展示在覆盖层里
    overlayView.backgroundImage = snapshot

    // ③ 再显示覆盖层（此时底层 UI 状态已被冻结在快照里）
    panel.orderFrontRegardless()  // 不激活，不影响 z-order
}
```

### 使用 ScreenCaptureKit 采集（macOS 12.3+，推荐）

```swift
import ScreenCaptureKit

func captureSnapshot() async throws -> CGImage {
    let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )

    let config = SCStreamConfiguration()
    config.width = Int(NSScreen.main!.frame.width * NSScreen.main!.backingScaleFactor)
    config.height = Int(NSScreen.main!.frame.height * NSScreen.main!.backingScaleFactor)
    config.showsCursor = false   // 截图不包含光标

    let filter = SCContentFilter(display: content.displays[0], excludingWindows: [])

    // 单帧截图
    return try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: config
    )
}
```

> **踩坑记录**：ScreenCaptureKit 需要用户授权 Screen Recording 权限，首次调用会弹出系统权限弹窗 。应在 app 启动时提前检测，不要在截图时才触发弹窗打断用户。 [fazm](https://fazm.ai/blog/screencapturekit-swift-api-guide)

### 排除自身覆盖层窗口

```swift
// 截图时排除自己的覆盖层，避免截图里出现 UI 控件
let myWindows = NSApp.windows.compactMap { $0 as? OverlayPanel }
let filter = SCContentFilter(
    display: display,
    excludingWindows: myWindows.compactMap { SCWindow(nsWindow: $0) }
)
```

***

## 四、键盘事件处理

### 全局快捷键触发不打断输入法

使用 `NSEvent.addGlobalMonitorForEvents` 监听快捷键，不抢夺 key window：

```swift
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    // Cmd+Shift+4 触发截图
    if event.modifierFlags.contains([.command, .shift]),
       event.keyCode == 21 {  // keyCode 21 = '4'
        self.activateScreenshot()
    }
}
```

> **踩坑记录**：`addGlobalMonitorForEvents` 在沙盒 app 里对 `.keyDown` 有限制，建议使用 `MASShortcut` 或 `KeyboardShortcuts` 三方库，底层走 Carbon `RegisterEventHotKey`，完全不干扰原 app 。 [stackoverflow](https://stackoverflow.com/questions/49716420/adding-a-global-monitor-with-nseventmaskkeydown-mask-does-not-trigger)

### Esc 取消不产生副作用

```swift
// 在 OverlayView 里处理 Esc
override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Esc
        dismissOverlay()
        // ⚠️ 不要调用 super.keyDown，否则会产生系统 beep 音
        return
    }
    // 其他按键也吞掉，不传给底层 app
}
```

***

## 五、显示与隐藏覆盖层

### 显示：不激活 app

```swift
// ✅ 正确：不激活，不影响原 app 的 active 状态
panel.orderFrontRegardless()

// ❌ 错误：会激活截图 app，导致原 app 失活
panel.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
```

### 隐藏：不把焦点给截图工具

```swift
func dismissOverlay() {
    panel.orderOut(nil)
    // ⚠️ 不要调用 NSApp.hide()，不要 activate 截图 app 自身
    // 原 app 会自动恢复 active 状态
}
```

***

## 六、光标管理

### 截图期间替换光标

```swift
// 进入截图模式：换成十字光标
NSCursor.crosshair.push()

// 退出截图模式：恢复原光标
NSCursor.pop()
```

> **踩坑记录**：用 `push/pop` 而不是 `set`，确保退出后光标正确恢复。如果用 `NSCursor.crosshair.set()`，退出后需要手动 `NSCursor.arrow.set()`，容易遗漏 。 [stackoverflow](https://stackoverflow.com/questions/25728111/prevent-activating-the-application-when-clicking-on-nswindow-nsview)

### 覆盖层区域外的光标

```swift
// 当鼠标在选框外时恢复箭头，在选框内时显示移动光标
override func resetCursorRects() {
    addCursorRect(selectionRect, cursor: .openHand)
    // selectionRect 外部区域自动使用 crosshair（在 mouseMoved 里 set）
}
```

***

## 七、多显示器与 HiDPI

### 为每块屏幕创建独立覆盖层

```swift
var overlayPanels: [OverlayPanel] = []

func setupOverlays() {
    for screen in NSScreen.screens {
        let panel = OverlayPanel()
        panel.setFrame(screen.frame, display: false)

        // 关键：将 panel 关联到正确的 screen
        // 否则在非主屏上 frame 坐标会错位
        overlayPanels.append(panel)
    }
}
```

### HiDPI 截图坐标换算

```swift
// 屏幕逻辑坐标 → 物理像素
let scale = screen.backingScaleFactor
let physicalRect = CGRect(
    x: logicalRect.origin.x * scale,
    y: logicalRect.origin.y * scale,
    width: logicalRect.width * scale,
    height: logicalRect.height * scale
)

// macOS 坐标系 y 轴方向与 CoreGraphics 相反，需翻转
let screenHeight = screen.frame.height * scale
let flippedRect = CGRect(
    x: physicalRect.origin.x,
    y: screenHeight - physicalRect.origin.y - physicalRect.height,
    width: physicalRect.width,
    height: physicalRect.height
)
```

> **踩坑记录**：macOS AppKit 坐标系原点在左下角，CoreGraphics（截图）坐标系原点在左上角，两者 y 轴方向相反，必须翻转。忘记翻转会导致截图内容在纵向上错位。

***

## 八、权限检测

### 提前检测 Screen Recording 权限

```swift
import ScreenCaptureKit

func checkScreenRecordingPermission() async -> Bool {
    do {
        // 尝试获取可分享内容，触发权限检测
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return true
    } catch {
        // 未授权
        return false
    }
}

// app 启动时调用，不要等到用户按下快捷键
Task {
    let hasPermission = await checkScreenRecordingPermission()
    if !hasPermission {
        showPermissionOnboardingUI()
    }
}
```

### Accessibility 权限（如需 CGEventTap 拦截模式）

```swift
let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
let isTrusted = AXIsProcessTrustedWithOptions(options)
```

***

## 九、安全输入字段与 DRM

```swift
// 检测当前是否处于 Secure Input 状态（密码框激活中）
// 此时截图内容会被系统自动遮蔽，截图工具无需额外处理
if IsSecureEventInputEnabled() {
    // 可选：提示用户当前为安全输入模式，截图区域可能为黑
    showSecureInputWarning()
}
```

DRM 内容（如 Netflix）在 `SCScreenshotManager` 截图时自动显示黑屏，这是系统行为，截图工具无需也不应绕过。

***

## 十、完整激活流程总结

```
用户按下快捷键
    │
    ├─① 检查权限（Screen Recording）
    │
    ├─② 采集当前屏幕快照（ScreenCaptureKit，排除自身窗口）
    │       此时目标 app 仍是 active，菜单/hover 状态完整保留在快照里
    │
    ├─③ 初始化 OverlayPanel（nonActivatingPanel + screenSaver level）
    │
    ├─④ 将快照设为覆盖层背景
    │
    ├─⑤ panel.orderFrontRegardless()（不激活，不触发 resignActive）
    │
    ├─⑥ NSCursor.crosshair.push()
    │
    ├─⑦ 用户拖拽选区（hitTest 吃掉事件，不穿透）
    │
    ├─⑧ 截图：对快照图裁剪选区 rect（或二次调用 SCScreenshotManager）
    │
    ├─⑨ panel.orderOut(nil)
    │
    ├─⑩ NSCursor.pop()
    │
    └─⑪ 保存/复制图片，完成
```

***

## 十一、推荐三方库

| 需求 | 推荐库 |
|---|---|
| 全局快捷键 | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（Swift，沙盒友好） |
| 窗口高亮识别 | 用 `ScreenCaptureKit` 枚举 `SCWindow` 获取每个窗口 frame |
| 取色器 | `NSColorSampler`（macOS 10.15+，系统原生） |
| 权限管理 | [PermissionsKit](https://github.com/sparrowcode/PermissionsKit) |

***

## 十二、常见踩坑速查表

| 症状 | 原因 | 解决方案 |
|---|---|---|
| 激活截图后菜单消失 | 用了 `makeKeyAndOrderFront` | 改用 `orderFrontRegardless` + `nonActivatingPanel` |
| 截图结果包含选框 UI | 先显示覆盖层再截图 | 先截图，再显示覆盖层 |
| 底层窗口 hover 效果消失 | `hitTest` 返回 nil 导致事件穿透 | `hitTest` 返回 self，吞掉鼠标事件 |
| 截图内容纵向错位 | 忘记翻转 y 轴 | CoreGraphics y 轴翻转公式 |
| 退出后光标残留十字 | 用了 `NSCursor.set()` 而非 `push/pop` | 改用 `push/pop` 配对 |
| Esc 取消时有 beep 声 | `keyDown` 调用了 `super` | 不要调用 `super.keyDown` |
| 第二块屏幕覆盖层位置错误 | 未给每块屏幕独立创建 panel | 遍历 `NSScreen.screens` 逐一创建 |
| 快捷键在输入法候选词期间失效 | 用了 `addGlobalMonitorForEvents` 监听 keyDown | 改用 Carbon `RegisterEventHotKey` |
