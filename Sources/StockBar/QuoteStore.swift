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
    @Published private(set) var launchAtLogin = LaunchAgent.isEnabled
    @Published private(set) var history: [String: HistoryClient.Series] = [:]   // code -> 日收盤

    private var historyFetchedAt: [String: Date] = [:]

    /// menu bar 標題需要重畫時呼叫
    var onChange: (() -> Void)?

    private var timer: Timer?

    init() { config = ConfigStore.load() }

    var L: L10n { L10n(lang: config.lang) }

    // MARK: - 輪詢

    func start() {
        refresh(force: true)
        scheduleNext()
        // 合蓋期間 timer 不會 fire，醒來先補一次，避免看到過期價格
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(force: true)
            self?.scheduleNext()
        }
    }

    /// 有市場開著（台股 / 美股盤中、或有追蹤幣）：依設定秒數跑；否則 60 秒一次。
    /// 每次都呼叫 refresh()，實際要不要打 API 由 isDue 決定——沒到期就零網路。
    func scheduleNext() {
        timer?.invalidate()
        let now = Date()
        let active = TradingCalendar.isOpen(now)
            || (TradingCalendar.isUSOpen(now) && !config.usStocks.isEmpty)
            || !config.cryptos.isEmpty
        let interval = active ? config.refresh : 60
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNext()
        }
        t.tolerance = max(1, interval / 5)   // 讓 macOS 合併喚醒、省電
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    enum Market: CaseIterable { case tw, us, crypto }

    private var lastFetch: [Market: Date] = [:]
    private static let closedInterval: TimeInterval = 30 * 60

    func isOpen(_ m: Market, _ now: Date = Date()) -> Bool {
        switch m {
        case .tw: return TradingCalendar.isOpen(now)
        case .us: return TradingCalendar.isUSOpen(now)
        case .crypto: return true
        }
    }

    /// 開盤：依間隔（美股最快 60 秒，Yahoo 較容易限流）；
    /// 收盤：收盤前抓的要補抓一次最終價，之後 30 分鐘一次
    private func isDue(_ m: Market, _ now: Date) -> Bool {
        guard let last = lastFetch[m] else { return true }
        let elapsed = now.timeIntervalSince(last)
        if isOpen(m, now) {
            let interval = m == .us ? max(60, config.refresh) : config.refresh
            return elapsed >= interval * 0.8   // 容忍 timer 提早觸發
        }
        let market: TradingCalendar.Market = m == .tw ? .tw : .us
        if let close = TradingCalendar.lastClose(market, before: now), last < close { return true }
        return elapsed >= Self.closedInterval
    }

    /// force：手動重新整理 / 喚醒 / 設定變更，無視間隔全抓
    func refresh(force: Bool = false) {
        config = ConfigStore.load()   // 熱重載：使用者手動編輯設定檔後自動生效
        let now = Date()
        func take(_ m: Market, _ syms: [SymbolConfig]) -> [SymbolConfig] {
            guard !syms.isEmpty, force || isDue(m, now) else { return [] }
            lastFetch[m] = now
            return syms
        }
        let jobs: [(Market, [SymbolConfig])] = [
            (.tw, take(.tw, config.stocks)),
            (.us, take(.us, config.usStocks)),
            (.crypto, take(.crypto, config.cryptos)),
        ].filter { !$0.1.isEmpty }
        refreshHistory()
        guard !jobs.isEmpty else { return }

        let group = DispatchGroup()
        var merged: [String: Quote] = [:]   // 只在 main queue 寫入
        for (m, syms) in jobs {
            group.enter()
            let done = { [weak self] (r: [String: Quote]) in
                DispatchQueue.main.async {
                    merged.merge(r) { $1 }
                    // 收盤市場抓失敗：1 分鐘後可重試，不必等 30 分鐘
                    if r.isEmpty, let self = self, !self.isOpen(m, now) {
                        self.lastFetch[m] = now.addingTimeInterval(-Self.closedInterval + 60)
                    }
                    group.leave()
                }
            }
            switch m {
            case .tw: TWSEClient.fetchMany(syms, completion: done)
            case .us: USStockClient.fetchMany(syms, isOpen: isOpen(.us, now), completion: done)
            case .crypto: CryptoClient.fetchMany(syms, currency: config.currency, completion: done)
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // 合併而非覆蓋：單一來源失敗或本輪沒抓時保留上一筆
            self.quotes.merge(merged) { $1 }
            self.fillMissingCost()
            self.onChange?()
        }
    }

    /// 期間 > 1 天才需要歷史收盤；日線一天才變一次，每檔 30 分鐘內不重抓
    private func refreshHistory() {
        guard config.days > 1 else { return }
        let now = Date()
        for sym in config.symbols where sym.amount != nil {
            if let t = historyFetchedAt[sym.code], now.timeIntervalSince(t) < 30 * 60 { continue }
            historyFetchedAt[sym.code] = now
            HistoryClient.fetch(sym) { [weak self] series in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let series = series, !series.isEmpty {
                        self.history[sym.code] = series
                        self.onChange?()
                    } else {
                        // 失敗 5 分鐘後重試，不要每輪都打
                        self.historyFetchedAt[sym.code] = Date().addingTimeInterval(-25 * 60)
                    }
                }
            }
        }
    }

    // MARK: - 讀取

    var activeSymbol: SymbolConfig? {
        let i = config.activeIndex ?? 0
        return config.symbols.indices.contains(i) ? config.symbols[i] : config.symbols.first
    }

    var privacy: Bool { config.privacyMode ?? false }

    /// 主畫面要列出的標的（隱私模式時略過標成隱藏的）
    var visibleSymbols: [SymbolConfig] {
        privacy ? config.symbols.filter { !($0.hideInPrivacy ?? false) } : config.symbols
    }

    var hiddenCount: Int { config.symbols.count - visibleSymbols.count }

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

    /// 期間標題：1 天 = 今日，其餘「近 N 天」
    var periodLabel: String {
        config.days == 1 ? L.t("Today", "今日") : L.t("\(config.days)D", "近\(config.days)天")
    }

    /// 期間損益（台幣）= 數量 × (現價 − 基準價)，以當下匯率換台幣（不含匯率變動）。
    /// 1 天：基準 = 昨收（幣沒有收盤，是 24 小時前價格）；
    /// N 天：基準 = N 個日曆天前（含）最後一個交易日收盤。
    func periodPnL(_ sym: SymbolConfig) -> Double? {
        guard let amt = sym.amount, let q = quotes[sym.code], let pTWD = q.twdPrice, q.price > 0 else { return nil }
        if config.days == 1 {
            guard q.prevClose > 0 else { return nil }
            return amt * q.change * (pTWD / q.price)
        }
        // 歷史收盤是原幣（台股 TWD、美股 USD、幣 USDT），現價也要用原幣比
        guard let native = sym.isTW ? q.price : q.usdPrice, native > 0,
              let series = history[sym.code],
              let base = HistoryClient.close(in: series, onOrBefore: Date().addingTimeInterval(-Double(config.days) * 86400))
        else { return nil }
        return amt * (native - base) * (pTWD / native)
    }

    /// 計入總損益的持倉，期間損益合計；% 以期初市值為分母
    var periodTotal: (pnl: Double, pct: Double)? {
        var pnl = 0.0, value = 0.0, any = false
        for sym in config.symbols where sym.inTotal {
            guard let d = periodPnL(sym), let h = holding(sym) else { continue }
            pnl += d
            value += h.value
            any = true
        }
        guard any else { return nil }
        let yesterday = value - pnl
        return (pnl, yesterday == 0 ? 0 : pnl / yesterday * 100)
    }

    /// 計入的持倉裡有幣且期間 = 1 天：今日損益是 24 小時漲跌，不是自然日
    var todayIncludesCrypto: Bool {
        config.days == 1 && config.symbols.contains { $0.inTotal && $0.amount != nil && $0.isCrypto }
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
        visibleSymbols.filter { $0.amount != nil && !$0.inTotal }.map(\.code)
    }

    func togglePrivacy() { mutate { $0.privacyMode = $0.privacyMode == true ? nil : true } }

    func setHideInPrivacy(_ code: String, _ hide: Bool) {
        guard let i = config.symbols.firstIndex(where: { $0.code == code }) else { return }
        mutate { $0.symbols[i].hideInPrivacy = hide ? true : nil }
    }

    func setInTotal(_ code: String, _ on: Bool) {
        guard let i = config.symbols.firstIndex(where: { $0.code == code }) else { return }
        mutate { $0.symbols[i].excludeFromTotal = on ? nil : true }
    }

    func setPnLDays(_ d: Int) {
        mutate { $0.pnlDays = min(30, max(1, d)) == 1 ? nil : min(30, max(1, d)) }
        refreshHistory()
    }

    func setMenuBarToday(_ today: Bool) { mutate { $0.menuBarPnL = today ? nil : "total" } }

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
        refresh(force: true)
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
        refresh(force: true)
    }

    func setLanguage(_ l: AppLanguage) { mutate { $0.language = l.rawValue } }

    func setLaunchAtLogin(_ on: Bool) {
        if on { LaunchAgent.enable() } else { LaunchAgent.disable() }
        launchAtLogin = LaunchAgent.isEnabled
    }

}
