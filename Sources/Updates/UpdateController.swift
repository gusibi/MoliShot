import AppKit
import Sparkle

/// One updater for both the application menu and the status-item menu.
final class UpdateController: NSObject, SPUUpdaterDelegate, NSMenuItemValidation {
    static let shared = UpdateController()

    private var controller: SPUStandardUpdaterController!
    private var pendingInstallation: (() -> Void)?
    private var installationInProgress = false

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    func start() {
        // Development builds must not replace themselves with a public release.
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: text("检查更新…", "Check for Updates…"), action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        #if DEBUG
        menuItem.title = text("检查更新（仅发行版）", "Check for Updates (Release Only)")
        return false
        #else
        menuItem.title = pendingInstallation == nil
            ? text("检查更新…", "Check for Updates…")
            : text("安装已下载的更新…", "Install Downloaded Update…")
        return pendingInstallation != nil || controller.updater.canCheckForUpdates
        #endif
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        if let install = pendingInstallation {
            guard readyToRestart() else { return }
            pendingInstallation = nil
            install()
        } else {
            controller.checkForUpdates(sender)
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        installationInProgress = true
    }

    // Sparkle can resume a prior install without invoking the postpone callback.
    func mayTerminateForUpdate() -> Bool {
        !installationInProgress || readyToRestart()
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !readyToRestart() else { return false }
        pendingInstallation = installHandler
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        pendingInstallation = nil
        installationInProgress = false
    }

    private func readyToRestart() -> Bool {
        guard AppCoordinator.shared.hasWorkToFinishBeforeUpdate else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = text("请先完成截图操作", "Finish Your Screenshots First")
        alert.informativeText = text(
            "请保存并关闭截图编辑窗口，关闭贴图和文字识别窗口，结束正在进行的截图或取色，然后从菜单选择「安装已下载的更新」。暂存栏和历史记录会保留。",
            "Save and close screenshot editors, close pinned images and text recognition windows, and finish any capture or color picking. Then choose Install Downloaded Update from the menu. Your shelf and history will be kept.")
        alert.addButton(withTitle: text("返回处理", "Go Back"))
        alert.runModal()
        return false
    }

    private func text(_ zh: String, _ en: String) -> String { L10n.isChinese ? zh : en }
}
