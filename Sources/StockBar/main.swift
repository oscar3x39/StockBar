import AppKit
import SwiftUI

/// 可成為 key 的無邊框面板，讓設定頁的輸入框能接收鍵盤
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// AppKit 殼：menu bar 標題 + 無箭頭面板（SwiftUI）。業務邏輯都在 QuoteStore。
/// 面板版面比照 ClaudeBar。
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = QuoteStore()
    private var statusItem: NSStatusItem!
    private var panel: KeyablePanel!
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "StockBar …"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        installEditMenu()

        // 無邊框面板：沒有 NSPopover 的箭頭；圓角與陰影由 SwiftUI 內容處理
        let p = KeyablePanel(contentRect: .zero,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.hidesOnDeactivate = false
        p.animationBehavior = .utilityWindow
        panel = p

        store.onChange = { [weak self] in self?.updateTitle() }
        store.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(closePanel),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    // MARK: - menu bar 標題

    private func updateTitle() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let L = store.L
        if store.showingHoldings {
            // 台幣損益：「今日 ▲+1,234 (+0.37%)」或「累計 ▲…」
            let today = store.config.menuBarToday
            let label = today ? store.periodLabel : L.t("Total", "累計")
            let value: (pnl: Double, pct: Double)?
            if today {
                value = store.periodTotal
            } else {
                value = store.holdingsTotal.map { ($0.pnl, $0.pct) }
            }
            guard let t = value else {
                statusItem.button?.title = "\(label) …"; return
            }
            // 隱私模式只顯示 %
            let body = store.privacy ? Fmt.pct(t.pct) : "\(Fmt.signedMoney(t.pnl)) (\(Fmt.pct(t.pct)))"
            statusItem.button?.attributedTitle = NSAttributedString(
                string: "\(label) \(arrow(t.pnl))\(body)",
                attributes: [.foregroundColor: color(t.pnl), .font: font])
            return
        }
        if store.privacy, store.activeSymbol?.hideInPrivacy == true {
            statusItem.button?.title = "StockBar"
            return
        }
        guard let sym = store.activeSymbol, let q = store.quotes[sym.code] else {
            if store.quotes.isEmpty { statusItem.button?.title = "StockBar —" }
            return
        }
        // 「價格 ▲漲跌%」
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "\(Fmt.price(q.price)) \(arrow(q.change))\(Fmt.pct(q.changePct))",
            attributes: [.foregroundColor: color(q.change), .font: font])
    }

    private func arrow(_ v: Double) -> String { v > 0 ? "▲" : (v < 0 ? "▼" : "＝") }

    // 台股習慣：紅漲綠跌（與美股相反）
    private func color(_ v: Double) -> NSColor {
        v > 0 ? .systemRed : (v < 0 ? .systemGreen : .labelColor)
    }

    // MARK: - 面板

    @objc private func togglePanel() {
        if panel.isVisible { closePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button, let btnWin = button.window else { return }

        // 開啟才建 SwiftUI 內容（狀態也每次重建）、關閉即拆，idle 時零渲染
        let root = PopoverView(store: store, ui: PanelState(), onQuit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        store.refresh()

        // 依內容自適應大小，置於 status item 正下方、不超出螢幕
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: Style.width, height: 400)
        panel.setContentSize(size)
        let rect = btnWin.convertToScreen(button.convert(button.bounds, to: nil))
        var x = rect.midX - size.width / 2
        if let vf = (btnWin.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: rect.minY - size.height - 6))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 點面板外（含桌面 / 其他 app）即關閉
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.closePanel()
        }
    }

    @objc private func closePanel() {
        guard panel?.isVisible == true else { return }
        panel.orderOut(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        panel.contentViewController = nil
    }

    /// accessory app 不顯示主選單，但輸入框的 ⌘X/⌘C/⌘V/⌘A 要靠它分派（nil-target 走 responder chain）
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }
}

// menu-bar only，不進 Dock
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
