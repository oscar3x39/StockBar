import Foundation

/// 一檔追蹤標的
struct SymbolConfig: Codable, Equatable {
    let code: String        // 0050 / 2330 / 6488...
    var market: String?     // "tse"(上市，預設) 或 "otc"(上櫃)

    var ex: String { (market ?? "tse").lowercased() == "otc" ? "otc" : "tse" }
    /// TWSE API 的 ex_ch 片段，例：tse_0050.tw
    var exCh: String { "\(ex)_\(code).tw" }
}

/// app 設定（可多檔）
struct AppConfig: Codable {
    var symbols: [SymbolConfig]
    var refreshSeconds: Int?
    var activeIndex: Int?

    var refresh: TimeInterval { TimeInterval(max(5, refreshSeconds ?? 15)) }

    static let `default` = AppConfig(
        symbols: [SymbolConfig(code: "0050", market: "tse")],
        refreshSeconds: 15,
        activeIndex: 0
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
