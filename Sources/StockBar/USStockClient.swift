import Foundation

/// 美股：Yahoo Finance chart API（免 key、非官方，可能改版或限流——失敗時該檔本輪不更新）。
/// 台幣價 = 美元價 × Yahoo USD/TWD（TWD=X）。
enum USStockClient {

    static func fetchMany(_ symbols: [SymbolConfig], isOpen: Bool,
                          completion: @escaping ([String: Quote]) -> Void) {
        guard !symbols.isEmpty else { completion([:]); return }
        let group = DispatchGroup()
        let lock = NSLock()
        var metas: [String: [String: Any]] = [:]
        var usdTWD: Double?

        for sym in symbols {
            group.enter()
            fetchMeta(sym.code) { m in
                if let m = m { lock.lock(); metas[sym.code] = m; lock.unlock() }
                group.leave()
            }
        }
        group.enter()
        fetchMeta("TWD=X") { m in
            lock.lock(); usdTWD = num(m?["regularMarketPrice"]); lock.unlock()
            group.leave()
        }
        group.notify(queue: .global()) {
            var out: [String: Quote] = [:]
            for (code, m) in metas {
                guard let price = num(m["regularMarketPrice"]), price > 0 else { continue }
                // range=1d 時 chartPreviousClose 即前一交易日收盤
                let prev = num(m["chartPreviousClose"]) ?? num(m["previousClose"]) ?? price
                out[code] = Quote(code: code, name: (m["shortName"] as? String) ?? code,
                                  price: price, prevClose: prev, time: "", isLive: isOpen,
                                  unit: "USD", usdPrice: price, twdPrice: usdTWD.map { price * $0 })
            }
            completion(out)
        }
    }

    private static func fetchMeta(_ symbol: String, completion: @escaping ([String: Any]?) -> Void) {
        let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=1d&range=1d") else {
            completion(nil); return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        // 無 UA 時 Yahoo 常回 429
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = obj["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let meta = result["meta"] as? [String: Any] else {
                completion(nil); return
            }
            completion(meta)
        }.resume()
    }

    private static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
}
