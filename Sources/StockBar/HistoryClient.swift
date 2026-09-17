import Foundation

/// 日收盤價歷史（近 N 天損益用）。回傳 [(日期, 收盤)]，由舊到新，已略過空值。
/// - 台股 / 美股：Yahoo Finance chart（台股上市 .TW、上櫃 .TWO）
/// - 幣：Binance 日 K（USDT，日期用收盤時間，未收完的當日 K 其收盤時間在未來）
enum HistoryClient {
    typealias Series = [(date: Date, close: Double)]

    static func fetch(_ sym: SymbolConfig, completion: @escaping (Series?) -> Void) {
        if sym.isCrypto { fetchBinance(sym.code, completion: completion) } else { fetchYahoo(sym, completion: completion) }
    }

    private static func fetchYahoo(_ sym: SymbolConfig, completion: @escaping (Series?) -> Void) {
        let ticker = sym.isUS ? sym.code : "\(sym.code).\(sym.ex == "otc" ? "TWO" : "TW")"
        let enc = ticker.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ticker
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=1d&range=2mo") else {
            completion(nil); return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = ((obj["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
                  let ts = result["timestamp"] as? [NSNumber],
                  let quote = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first,
                  let closes = quote["close"] as? [Any] else {
                completion(nil); return
            }
            var out: Series = []
            for (t, c) in zip(ts, closes) {
                guard let v = (c as? NSNumber)?.doubleValue, v > 0 else { continue }   // Yahoo 偶有 null
                out.append((Date(timeIntervalSince1970: t.doubleValue), v))
            }
            completion(out)
        }.resume()
    }

    private static func fetchBinance(_ code: String, completion: @escaping (Series?) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/klines?symbol=\(code.uppercased())USDT&interval=1d&limit=40") else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 10)) { data, _, _ in
            guard let data = data,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                completion(nil); return
            }
            let out: Series = rows.compactMap { k in
                guard k.count > 6, let closeTime = (k[6] as? NSNumber)?.doubleValue,
                      let close = Double(k[4] as? String ?? ""), close > 0 else { return nil }
                return (Date(timeIntervalSince1970: closeTime / 1000), close)
            }
            completion(out)
        }.resume()
    }

    /// 基準價：日期不晚於 cutoff 的最後一筆收盤
    static func close(in series: Series, onOrBefore cutoff: Date) -> Double? {
        series.last { $0.date <= cutoff }?.close
    }
}
