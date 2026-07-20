import AppKit

/// menu-bar app：顯示台股即時價（可多檔設定），盤中每 15s 更新（時差 <1 分鐘）
final class StockBarApp: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var config = AppConfig.default
    private var quotes: [String: Quote] = [:]   // code -> 最新報價

    // 台股習慣：紅漲綠跌（與美股相反）
    private let upColor = NSColor.systemRed
    private let downColor = NSColor.systemGreen
    private let flatColor = NSColor.labelColor

    private var activeSymbol: SymbolConfig? {
        let i = config.activeIndex ?? 0
        return config.symbols.indices.contains(i) ? config.symbols[i] : config.symbols.first
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "StockBar …"
        config = ConfigStore.load()
        buildMenu()
        refresh()
        scheduleNext()
    }

    // MARK: - 排程（盤中依設定秒數、盤後拉長到 5 分鐘省流量）
    private func scheduleNext() {
        timer?.invalidate()
        let interval: TimeInterval = TradingCalendar.isOpen(Date()) ? config.refresh : 300
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNext()   // 依當下盤別 / 最新設定重新決定間隔
        }
    }

    private func refresh() {
        config = ConfigStore.load()   // 熱重載：使用者編輯設定檔後自動生效
        let symbols = config.symbols
        TWSEClient.fetchMany(symbols) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !result.isEmpty { self.quotes = result }
                self.renderActive()
                self.buildMenu()
            }
        }
    }

    // MARK: - 畫面
    private func renderActive() {
        guard let sym = activeSymbol, let q = quotes[sym.code] else {
            if quotes.isEmpty { statusItem.button?.title = "StockBar —" }
            return
        }
        statusItem.button?.attributedTitle = titleAttr(for: q, prefixCode: false)
    }

    /// 產生「代號 價格 ▲漲跌%」的著色字串
    private func titleAttr(for q: Quote, prefixCode: Bool) -> NSAttributedString {
        let arrow = q.change > 0 ? "▲" : (q.change < 0 ? "▼" : "＝")
        let color = q.change > 0 ? upColor : (q.change < 0 ? downColor : flatColor)
        let head = prefixCode ? "\(q.code) " : ""
        let title = String(format: "%@%.2f %@%+.2f%%", head, q.price, arrow, q.changePct)
        return NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
        ])
    }

    private func buildMenu() {
        let menu = NSMenu()
        let activeCode = activeSymbol?.code

        // 每檔一列：點選即設為作用中（顯示在 menu bar）
        for (i, sym) in config.symbols.enumerated() {
            let item = NSMenuItem(title: "", action: #selector(selectSymbol(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (sym.code == activeCode) ? .on : .off
            if let q = quotes[sym.code] {
                let mut = NSMutableAttributedString(string: "\(q.name)  ")
                mut.append(titleAttr(for: q, prefixCode: false))
                let live = q.isLive ? "" : "  ·closed"
                mut.append(NSAttributedString(string: live, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                item.attributedTitle = mut
            } else {
                item.title = "\(sym.code)  Loading…"
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        add(menu, "Add Symbol…", action: #selector(addSymbol))

        // Remove: submenu listing every tracked symbol
        let removeItem = NSMenuItem(title: "Remove Symbol", action: nil, keyEquivalent: "")
        if config.symbols.isEmpty {
            removeItem.isEnabled = false
        } else {
            let sub = NSMenu()
            for (i, sym) in config.symbols.enumerated() {
                let name = quotes[sym.code]?.name ?? sym.code
                let it = NSMenuItem(title: "\(name) (\(sym.code))", action: #selector(removeSymbol(_:)), keyEquivalent: "")
                it.target = self
                it.tag = i
                sub.addItem(it)
            }
            removeItem.submenu = sub
        }
        menu.addItem(removeItem)

        menu.addItem(.separator())
        let login = add(menu, "Launch at Login", action: #selector(toggleLaunchAtLogin))
        login.state = LaunchAgent.isEnabled ? .on : .off
        add(menu, "Refresh Now", action: #selector(manualRefresh))
        add(menu, "Open Config…", action: #selector(openConfig))
        add(menu, "Quit", action: #selector(quit), key: "q")
        statusItem.menu = menu
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, action: Selector? = nil,
                     key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - 動作
    @objc private func selectSymbol(_ sender: NSMenuItem) {
        guard config.symbols.indices.contains(sender.tag) else { return }
        config.activeIndex = sender.tag
        ConfigStore.save(config)      // 記住選擇
        renderActive()
        buildMenu()
    }

    @objc private func addSymbol() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add Symbol"
        alert.informativeText = "Enter a stock code (e.g. 2330). Check the box for OTC (上櫃) stocks."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 24, width: 220, height: 24))
        field.placeholderString = "Stock code"
        let otc = NSButton(checkboxWithTitle: "OTC (上櫃)", target: nil, action: nil)
        otc.frame = NSRect(x: 0, y: 0, width: 220, height: 20)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 48))
        container.addSubview(field)
        container.addSubview(otc)
        alert.accessoryView = container
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let code = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        guard !config.symbols.contains(where: { $0.code == code }) else { return }  // 去重
        config.symbols.append(SymbolConfig(code: code, market: otc.state == .on ? "otc" : "tse"))
        ConfigStore.save(config)
        refresh()
    }

    @objc private func removeSymbol(_ sender: NSMenuItem) {
        guard config.symbols.indices.contains(sender.tag) else { return }
        config.symbols.remove(at: sender.tag)
        // active 索引防呆
        let i = config.activeIndex ?? 0
        config.activeIndex = config.symbols.isEmpty ? 0 : min(i, config.symbols.count - 1)
        ConfigStore.save(config)
        refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        if LaunchAgent.isEnabled { LaunchAgent.disable() } else { LaunchAgent.enable() }
        buildMenu()
    }

    @objc private func manualRefresh() { refresh() }

    @objc private func openConfig() {
        ConfigStore.save(config)      // 確保檔案存在再開
        NSWorkspace.shared.open(ConfigStore.file)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// menu-bar only，不進 Dock
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = StockBarApp()
app.delegate = delegate
app.run()
