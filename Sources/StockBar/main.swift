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
                let live = q.isLive ? "" : "  ·收盤"
                mut.append(NSAttributedString(string: live, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                item.attributedTitle = mut
            } else {
                item.title = "\(sym.code)  載入中…"
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        add(menu, "立即更新", action: #selector(manualRefresh))
        add(menu, "開啟設定檔…", action: #selector(openConfig))
        add(menu, "結束", action: #selector(quit), key: "q")
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
