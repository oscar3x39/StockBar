import AppKit

/// 一筆持倉（一律台幣）
struct Holding {
    let value: Double   // 現在市值
    let cost: Double    // 總成本
    var pnl: Double { value - cost }
    var pct: Double { cost == 0 ? 0 : pnl / cost * 100 }
}

/// 狀態中心：設定、報價、輪詢、持倉計算與所有使用者動作。
/// UI（menu bar 標題、面板）只讀這裡、只呼叫這裡的方法。全部在 main thread 操作。
final class QuoteStore: ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var quotes: [String: Quote] = [:]   // code -> 最新報價
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var launchAtLogin = LaunchAgent.isEnabled

    /// menu bar 標題需要重畫時呼叫
    var onChange: (() -> Void)?

    private var timer: Timer?

    init() { config = ConfigStore.load() }

    var L: L10n { L10n(lang: config.lang) }

    // MARK: - 輪詢

    func start() {
        refresh()
        scheduleNext()
        // 合蓋期間 timer 不會 fire，醒來先補一次，避免看到過期價格
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
            self?.scheduleNext()
        }
    }

    /// 任一市場開著（台股盤中 / 美股盤中 / 有追蹤幣）：依設定秒數輪詢，只抓開著的市場；
    /// 否則只留 60s 本地時鐘等開盤（零網路）
    func scheduleNext() {
        timer?.invalidate()
        let now = Date()
        let twOpen = TradingCalendar.isOpen(now)
        let usOpen = TradingCalendar.isUSOpen(now) && !config.usStocks.isEmpty
        let t: Timer
        if twOpen || usOpen || !config.cryptos.isEmpty {
            t = Timer(timeInterval: config.refresh, repeats: false) { [weak self] _ in
                self?.refresh(includeTW: twOpen, includeUS: usOpen)
                self?.scheduleNext()
            }
            t.tolerance = max(1, config.refresh / 5)   // 讓 macOS 合併喚醒、省電
        } else {
            t = Timer(timeInterval: 60, repeats: false) { [weak self] _ in self?.scheduleNext() }
            t.tolerance = 10
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 收盤的市場不抓（價格不動）；手動 / 開面板 / 喚醒時預設全抓一次
    func refresh(includeTW: Bool = true, includeUS: Bool = true) {
        config = ConfigStore.load()   // 熱重載：使用者手動編輯設定檔後自動生效
        let stocks = includeTW ? config.stocks : []
        let us = includeUS ? config.usStocks : []
        let group = DispatchGroup()
        var merged: [String: Quote] = [:]   // 只在 main queue 寫入
        group.enter()
        TWSEClient.fetchMany(stocks) { r in
            DispatchQueue.main.async { merged.merge(r) { $1 }; group.leave() }
        }
        group.enter()
        CryptoClient.fetchMany(config.cryptos, currency: config.currency) { r in
            DispatchQueue.main.async { merged.merge(r) { $1 }; group.leave() }
        }
        group.enter()
        USStockClient.fetchMany(us, isOpen: TradingCalendar.isUSOpen(Date())) { r in
            DispatchQueue.main.async { merged.merge(r) { $1 }; group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // 合併而非覆蓋：單一來源失敗或本輪沒抓時保留上一筆
            self.quotes.merge(merged) { $1 }
            if !merged.isEmpty { self.lastUpdate = Date() }
            self.fillMissingCost()
            self.onChange?()
        }
    }

    // MARK: - 讀取

    var activeSymbol: SymbolConfig? {
        let i = config.activeIndex ?? 0
        return config.symbols.indices.contains(i) ? config.symbols[i] : config.symbols.first
    }

    var hasHoldings: Bool { config.symbols.contains { $0.amount != nil } }
    var showingHoldings: Bool { (config.menuBarShowsHoldings ?? false) && hasHoldings }

    /// 市值與成本一律換成台幣。美元成本以「當下」匯率換算，所以報酬率只反映美元價格變動；
    /// 台幣成本則是買進時固定的台幣，報酬率含匯率變動。
    func holding(_ sym: SymbolConfig) -> Holding? {
        guard let amt = sym.amount, let q = quotes[sym.code], let pTWD = q.twdPrice else { return nil }
        if sym.costInUSD {
            guard let c = sym.costUSD, let pUSD = q.usdPrice, pUSD > 0 else { return nil }
            return Holding(value: amt * pTWD, cost: amt * c * (pTWD / pUSD))
        }
        guard let c = sym.costTWD else { return nil }
        return Holding(value: amt * pTWD, cost: amt * c)
    }

    /// 計入總損益的持倉合計；沒有回 nil
    var holdingsTotal: Holding? {
        let hs = config.symbols.filter(\.inTotal).compactMap(holding)
        guard !hs.isEmpty else { return nil }
        return Holding(value: hs.reduce(0) { $0 + $1.value }, cost: hs.reduce(0) { $0 + $1.cost })
    }

    // MARK: - 動作

    private func mutate(_ change: (inout AppConfig) -> Void) {
        change(&config)
        ConfigStore.save(config)
        onChange?()
    }

    /// 該檔成本幣別下的現價
    private func currentPrice(_ sym: SymbolConfig) -> Double? {
        sym.costInUSD ? quotes[sym.code]?.usdPrice : quotes[sym.code]?.twdPrice
    }

    /// 有數量但沒成本：以當下市價（依成本幣別）為成本寫回（只寫一次）
    private func fillMissingCost() {
        let missing = config.symbols.indices.filter {
            let s = config.symbols[$0]
            return s.amount != nil && (s.costInUSD ? s.costUSD : s.costTWD) == nil && currentPrice(s) != nil
        }
        guard !missing.isEmpty else { return }
        mutate { cfg in
            for i in missing {
                let p = currentPrice(cfg.symbols[i])
                if cfg.symbols[i].costInUSD { cfg.symbols[i].costUSD = p } else { cfg.symbols[i].costTWD = p }
            }
        }
    }

    /// 點某檔：menu bar 改顯示該檔價格
    func select(_ code: String) {
        guard let i = config.symbols.firstIndex(where: { $0.code == code }) else { return }
        mutate { $0.activeIndex = i; $0.menuBarShowsHoldings = nil }
    }

    /// 有持倉但不計入總損益的代號
    var excludedCodes: [String] {
        config.symbols.filter { $0.amount != nil && !$0.inTotal }.map(\.code)
    }

    func setInTotal(_ code: String, _ on: Bool) {
        guard let i = config.symbols.firstIndex(where: { $0.code == code }) else { return }
        mutate { $0.symbols[i].excludeFromTotal = on ? nil : true }
    }

    func setShowHoldings(_ on: Bool) { mutate { $0.menuBarShowsHoldings = on ? true : nil } }

    /// 回傳錯誤訊息（已在 L 語系），成功回 nil
    func addSymbol(_ raw: String, market: String) -> String? {
        var code = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        code = code.trimmingCharacters(in: .whitespaces)
        if market == "crypto" || market == "us" { code = code.uppercased() }
        guard !code.isEmpty else { return L.t("Enter a code.", "請輸入代號。") }
        // 台股代號一定含數字（2330、00679B）；純英文多半是選錯市場的美股 / 幣
        if (market == "tse" || market == "otc") && !code.contains(where: \.isNumber) {
            return L.t("\(code) isn't a Taiwan code. Pick US or Crypto.",
                       "\(code) 不是台股代號，請改選「美股」或「加密貨幣」。")
        }
        guard !config.symbols.contains(where: { $0.code == code }) else {
            return L.t("\(code) is already in the list.", "\(code) 已在清單中。")
        }
        mutate { $0.symbols.append(SymbolConfig(code: code, market: market)) }
        refresh()
        scheduleNext()   // 新增幣 / 美股時，要依新市場重排輪詢
        return nil
    }

    func removeSymbol(_ code: String) {
        guard config.symbols.count > 1,
              let i = config.symbols.firstIndex(where: { $0.code == code }) else { return }
        let activeCode = activeSymbol?.code
        mutate { cfg in
            cfg.symbols.remove(at: i)
            cfg.activeIndex = cfg.symbols.firstIndex { $0.code == activeCode } ?? 0
        }
        quotes[code] = nil
        scheduleNext()
    }

    /// 儲存一檔持倉。amount 空 = 清除持倉；cost 空 = 用現價；inUSD = 成本以美元記。
    /// 回傳錯誤訊息或 nil
    func saveHolding(code: String, amount amountText: String, cost costText: String,
                     inUSD: Bool) -> String? {
        guard let i = config.symbols.firstIndex(where: { $0.code == code }) else { return nil }
        let blank = { (s: String) in s.trimmingCharacters(in: .whitespaces).isEmpty }
        if blank(amountText) {
            mutate {
                $0.symbols[i].amount = nil
                $0.symbols[i].costTWD = nil
                $0.symbols[i].costUSD = nil
                $0.symbols[i].costCurrency = nil
            }
            return nil
        }
        guard let amt = Fmt.parse(amountText), amt > 0 else {
            return L.t("\(code): quantity must be a positive number.", "\(code)：數量要是正數。")
        }
        var target = config.symbols[i]
        target.costCurrency = inUSD && !target.isTW ? "USD" : nil
        var cost: Double?
        if blank(costText) {
            cost = currentPrice(target)   // 還沒報價就留空，下一輪 fillMissingCost 補
        } else {
            guard let c = Fmt.parse(costText), c > 0 else {
                return L.t("\(code): cost must be a positive number.", "\(code)：成本要是正數。")
            }
            cost = c
        }
        target.amount = amt
        // 只留當前幣別的成本，避免切換後舊值殘留造成誤會
        target.costTWD = target.costInUSD ? nil : cost
        target.costUSD = target.costInUSD ? cost : nil
        mutate { $0.symbols[i] = target }
        return nil
    }

    func setCurrency(_ c: CryptoCurrency) {
        guard c != config.currency else { return }
        mutate { $0.cryptoCurrency = c.rawValue }
        // 丟掉舊幣別的報價，避免抓到新價前顯示錯單位的數字
        for sym in config.cryptos { quotes[sym.code] = nil }
        refresh()
    }

    func setLanguage(_ l: AppLanguage) { mutate { $0.language = l.rawValue } }

    func setLaunchAtLogin(_ on: Bool) {
        if on { LaunchAgent.enable() } else { LaunchAgent.disable() }
        launchAtLogin = LaunchAgent.isEnabled
    }

}
