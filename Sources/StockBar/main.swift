import AppKit

/// menu-bar app：顯示台股 0050 即時價，盤中每 15s 更新（時差 <1 分鐘）
final class StockBarApp: NSObject, NSApplicationDelegate {

    private let symbol = "0050"
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastQuote: Quote?

    // 台股習慣：紅漲綠跌（與美股相反）
    private let upColor = NSColor.systemRed
    private let downColor = NSColor.systemGreen
    private let flatColor = NSColor.labelColor

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "0050 …"
        buildMenu()
        refresh()
        scheduleNext()
    }

    // MARK: - 排程（盤中 15s、盤後拉長到 5 分鐘省流量）
    private func scheduleNext() {
        timer?.invalidate()
        let interval: TimeInterval = TradingCalendar.isOpen(Date()) ? 15 : 300
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNext()   // 依當下盤別重新決定間隔
        }
    }

    private func refresh() {
        TWSEClient.fetch(symbol) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let q):
                    self?.lastQuote = q
                    self?.render(q)
                case .failure:
                    self?.renderError()
                }
            }
        }
    }

    // MARK: - 畫面
    private func render(_ q: Quote) {
        let arrow = q.change > 0 ? "▲" : (q.change < 0 ? "▼" : "＝")
        let color = q.change > 0 ? upColor : (q.change < 0 ? downColor : flatColor)
        let priceStr = String(format: "%.2f", q.price)
        let pctStr = String(format: "%+.2f%%", q.changePct)
        let title = "\(symbol) \(priceStr) \(arrow)\(pctStr)"

        let attr = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
        ])
        statusItem.button?.attributedTitle = attr
        buildMenu()
    }

    private func renderError() {
        // 保留上一筆好資料，只在完全沒資料時顯示待命
        if lastQuote == nil { statusItem.button?.title = "0050 —" }
    }

    private func buildMenu() {
        let menu = NSMenu()
        if let q = lastQuote {
            let live = q.isLive ? "盤中" : "收盤/無量"
            add(menu, "\(q.name)（\(q.code)）", enabled: false)
            add(menu, String(format: "現價  %.2f", q.price), enabled: false)
            add(menu, String(format: "昨收  %.2f", q.prevClose), enabled: false)
            add(menu, String(format: "漲跌  %+.2f (%+.2f%%)", q.change, q.changePct), enabled: false)
            add(menu, "狀態  \(live)  \(q.time)", enabled: false)
            menu.addItem(.separator())
        }
        add(menu, "立即更新", action: #selector(manualRefresh))
        add(menu, "結束", action: #selector(quit), key: "q")
        statusItem.menu = menu
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, action: Selector? = nil,
                     key: String = "", enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled && action != nil
        menu.addItem(item)
        return item
    }

    @objc private func manualRefresh() { refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// menu-bar only，不進 Dock
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = StockBarApp()
app.delegate = delegate
app.run()
