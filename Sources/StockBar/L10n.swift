import Foundation

/// 介面中英文：呼叫端直接寫成對字串 `L.t("Settings", "設定")`，
/// 字串量小，比 .strings 檔好維護，也不需要 bundle resource。
struct L10n {
    let lang: AppLanguage
    func t(_ en: String, _ zh: String) -> String { lang == .zh ? zh : en }
}

/// 數字格式
enum Fmt {
    private static func formatter(_ minFrac: Int, _ maxFrac: Int, grouping: Bool = true) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")   // 固定 . 小數點、, 千分位
        f.usesGroupingSeparator = grouping
        f.minimumFractionDigits = minFrac
        f.maximumFractionDigits = maxFrac
        return f
    }
    private static let priceF = formatter(2, 2)
    private static let moneyF = formatter(0, 0)
    private static let plainF = formatter(0, 8, grouping: false)
    private static let amountF = formatter(0, 8)
    private static let plainCostF = formatter(0, 2, grouping: false)

    /// 價格：兩位小數、千分位
    static func price(_ v: Double) -> String { priceF.string(from: NSNumber(value: v)) ?? "\(v)" }
    /// 台幣金額：取到元
    static func money(_ v: Double) -> String { moneyF.string(from: NSNumber(value: v)) ?? "\(v)" }
    /// 帶正負號的台幣金額
    static func signedMoney(_ v: Double) -> String { (v < 0 ? "-" : "+") + money(abs(v)) }
    static func pct(_ v: Double) -> String { String(format: "%+.2f%%", v) }
    /// 顆數：原樣、最多 8 位
    static func amount(_ v: Double) -> String { amountF.string(from: NSNumber(value: v)) ?? "\(v)" }
    /// 輸入框用：無千分位
    static func plain(_ v: Double) -> String { plainF.string(from: NSNumber(value: v)) ?? "\(v)" }
    /// 成本輸入框用：最多 2 位小數、無千分位
    static func plainCost(_ v: Double) -> String { plainCostF.string(from: NSNumber(value: v)) ?? "\(v)" }

    /// 輸入清洗：全形轉半形（中文輸入法常打出 ０．０５）、去空白與千分位
    static func parse(_ s: String) -> Double? {
        let half = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        let t = half.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        return Double(t)
    }
}
