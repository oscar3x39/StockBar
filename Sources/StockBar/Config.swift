import Foundation

/// 一檔追蹤標的
struct SymbolConfig: Codable, Equatable {
    let code: String        // 0050 / 2330 / 6488...
    var market: String?     // "tse"(上市，預設)、"otc"(上櫃)、"us"(美股)、"crypto"(BTC/ETH…，對 USDT)

    var amount: Double?     // 持有數量（股 / 顆，選填，設定頁「持倉」填）
    var costTWD: Double?    // 每單位成本（台幣，固定不隨匯率變）；沒填時以當下台幣市價補上
    var costUSD: Double?    // 每單位成本（美元；幣視為 USDT）。costCurrency == "USD" 時使用
    var costCurrency: String?     // 成本幣別："USD"，nil = 台幣（台股固定台幣）
    var excludeFromTotal: Bool?   // true：個別仍顯示損益，但不併入總損益（nil = 計入）
    var hideInPrivacy: Bool?      // true：隱私模式時整列不顯示

    /// 成本以美元記：報酬率 = 美元價格變動（與券商一致），不含匯率
    var costInUSD: Bool { !isTW && costCurrency == "USD" }

    var inTotal: Bool { !(excludeFromTotal ?? false) }

    var isCrypto: Bool { (market ?? "").lowercased() == "crypto" }
    var isUS: Bool { (market ?? "").lowercased() == "us" }
    var isTW: Bool { !isCrypto && !isUS }

    var ex: String { (market ?? "tse").lowercased() == "otc" ? "otc" : "tse" }
    /// TWSE API 的 ex_ch 片段，例：tse_0050.tw
    var exCh: String { "\(ex)_\(code).tw" }
}

enum AppLanguage: String, CaseIterable {
    case en, zh

    /// 未設定時跟系統：系統首選語言是中文就用中文
    static var system: AppLanguage {
        (Locale.preferredLanguages.first ?? "").hasPrefix("zh") ? .zh : .en
    }
}

enum CryptoCurrency: String, CaseIterable {
    case usdt = "USDT"
    case twd = "TWD"
}

/// app 設定（可多檔）
struct AppConfig: Codable {
    var symbols: [SymbolConfig]
    var refreshSeconds: Int?
    var activeIndex: Int?
    var cryptoCurrency: String?   // 幣價計價："USDT"(預設) 或 "TWD"
    var menuBarShowsHoldings: Bool?  // true：menu bar 顯示持倉總損益，取代單檔價格
    var menuBarPnL: String?       // menu bar 損益顯示 "today"(預設) 或 "total"

    var pnlDays: Int?             // 期間損益天數 1–30（1 = 今日）

    var menuBarToday: Bool { menuBarPnL != "total" }
    var days: Int { min(30, max(1, pnlDays ?? 1)) }
    var language: String?         // "en" / "zh"；未設定跟系統
    var privacyMode: Bool?        // true：金額、數量一律遮住，只顯示 %

    var lang: AppLanguage { language.flatMap(AppLanguage.init(rawValue:)) ?? .system }

    var currency: CryptoCurrency { CryptoCurrency(rawValue: (cryptoCurrency ?? "").uppercased()) ?? .usdt }

    var refresh: TimeInterval { TimeInterval(max(5, refreshSeconds ?? 15)) }
    var stocks: [SymbolConfig] { symbols.filter { $0.isTW } }
    var usStocks: [SymbolConfig] { symbols.filter { $0.isUS } }
    var cryptos: [SymbolConfig] { symbols.filter { $0.isCrypto } }

    static let `default` = AppConfig(
        symbols: [SymbolConfig(code: "0050", market: "tse")],
        refreshSeconds: 15,
        activeIndex: 0,
        cryptoCurrency: nil,
        menuBarShowsHoldings: nil,
        language: nil,
        privacyMode: nil
    )
}

/// 設定檔讀寫：~/.config/StockBar/config.json
/// 首次執行自動建立預設；使用者手動編輯存檔後，下一輪輪詢自動生效。
enum ConfigStore {
    static var dir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/StockBar", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("config.json") }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: file),
              var cfg = try? JSONDecoder().decode(AppConfig.self, from: data),
              !cfg.symbols.isEmpty else {
            let d = AppConfig.default
            save(d)
            return d
        }
        // activeIndex 邊界防呆（使用者可能刪檔改亂）
        let idx = cfg.activeIndex ?? 0
        cfg.activeIndex = min(max(0, idx), cfg.symbols.count - 1)
        return cfg
    }

    static func save(_ cfg: AppConfig) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? enc.encode(cfg) {
            try? data.write(to: file)
        }
    }
}
