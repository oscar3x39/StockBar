import AppKit

/// menu-bar app：顯示台股即時價（可多檔設定），盤中每 15s 更新（時差 <1 分鐘）
final class StockBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var timer: Timer?
    /// 單一 menu 實例：選單開著時只改內容、不整個換掉（換掉的話開著那份不會更新）
    private let menu = NSMenu()
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
        menu.delegate = self
        statusItem.menu = menu
        buildMenu()
        refresh()
        scheduleNext()

        // 合蓋期間 timer 不會 fire，醒來先補一次，避免看到過期價格
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func didWake() {
        refresh()
        scheduleNext()
    }

    /// 選單一打開就補抓一次，滑鼠停在上面的期間也照常輪詢（timer 已註冊 .common mode）
    func menuWillOpen(_ menu: NSMenu) { refresh() }

    // MARK: - 排程（盤中依設定秒數、盤後拉長到 5 分鐘省流量）
    private func scheduleNext() {
        timer?.invalidate()
        if TradingCalendar.isOpen(Date()) {
            // 開盤：保持即時 ticker，依設定秒數輪詢。
            let t = Timer(timeInterval: config.refresh, repeats: false) { [weak self] _ in
                self?.refresh()
                self?.scheduleNext()
            }
            t.tolerance = max(1, config.refresh / 5)   // 讓 macOS 合併喚醒、省電
            // .common：選單展開（eventTracking mode）時 timer 照樣 fire
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            // 省電：收盤/週末/假日「完全不抓報價」——股價不動，抓了也一樣。
            // 只留一個 60s 時鐘檢查盤別（純本地計算、零網路），開盤後最多晚 1 分鐘恢復輪詢。
            let t = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
                self?.scheduleNext()
            }
            t.tolerance = 10
            RunLoop.main.add(t, forMode: .common)
            timer = t
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
                if !self.updateQuoteRows() { self.buildMenu() }
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

    /// 只重畫報價那幾列；選單開著時走這條，避免整份重建造成閃爍。
    /// 結構有變（增刪標的）回 false，交給 buildMenu 全建。
    private func updateQuoteRows() -> Bool {
        guard menu.numberOfItems >= config.symbols.count else { return false }
        for (i, sym) in config.symbols.enumerated() {
            guard let item = menu.item(at: i),
                  item.action == #selector(selectSymbol(_:)) else { return false }
            render(sym, into: item, index: i)
        }
        return true
    }

    private func render(_ sym: SymbolConfig, into item: NSMenuItem, index: Int) {
        item.target = self
        item.tag = index
        item.state = (sym.code == activeSymbol?.code) ? .on : .off
        if let q = quotes[sym.code] {
            let mut = NSMutableAttributedString(string: "\(q.name)  ")
            mut.append(titleAttr(for: q, prefixCode: false))
            let live = q.isLive ? "" : "  ·closed"
            mut.append(NSAttributedString(string: live, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = mut
        } else {
            item.title = "\(sym.code)  Loading…"
        }
    }

    private func buildMenu() {
        menu.removeAllItems()

        // 每檔一列：點選即設為作用中（顯示在 menu bar）
        for (i, sym) in config.symbols.enumerated() {
            let item = NSMenuItem(title: "", action: #selector(selectSymbol(_:)), keyEquivalent: "")
            render(sym, into: item, index: i)
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
