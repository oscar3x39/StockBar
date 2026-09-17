import Foundation

/// 美股：Yahoo Finance spark API（免 key、非官方，可能改版或限流——失敗時本輪不更新）。
/// 所有美股與 USD/TWD（TWD=X）合成 1 個請求；台幣價 = 美元價 × USD/TWD。
enum USStockClient {

    static func fetchMany(_ symbols: [SymbolConfig], isOpen: Bool,
                          completion: @escaping ([String: Quote]) -> Void) {
        guard !symbols.isEmpty else { completion([:]); return }
        let list = (symbols.map { $0.code.uppercased() } + ["TWD=X"]).joined(separator: ",")
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/spark")!
        comps.queryItems = [URLQueryItem(name: "symbols", value: list),
                            URLQueryItem(name: "range", value: "1d"),
                            URLQueryItem(name: "interval", value: "1d")]
        guard let url = comps.url else { completion([:]); return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        // 無 UA 時 Yahoo 常回 429
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                completion([:]); return
            }
            let usdTWD = last(obj["TWD=X"])?.price
            var out: [String: Quote] = [:]
            for sym in symbols {
                guard let m = obj[sym.code.uppercased()], let l = last(m), l.price > 0 else { continue }
                // range=1d 時 chartPreviousClose 即前一交易日收盤
                let prev = (m["chartPreviousClose"] as? NSNumber)?.doubleValue ?? l.price
                // 盤中資料時間用抓取當下；收盤後用該交易日（K 棒開盤時間）
                out[sym.code] = Quote(code: sym.code, name: sym.code,
                                      price: l.price, prevClose: prev, time: "", isLive: isOpen,
                                      unit: "USD", usdPrice: l.price,
                                      twdPrice: usdTWD.map { l.price * $0 },
                                      asOf: isOpen ? Date() : l.at)
            }
            completion(out)
        }.resume()
    }

    /// spark 每檔的最後一根 K：收盤價與時間
    private static func last(_ m: [String: Any]?) -> (price: Double, at: Date)? {
        guard let m = m,
              let closes = m["close"] as? [Any],
              let ts = m["timestamp"] as? [NSNumber],
              let c = (closes.last as? NSNumber)?.doubleValue, let t = ts.last else { return nil }
        return (c, Date(timeIntervalSince1970: t.doubleValue))
    }
}
