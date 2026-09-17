import Foundation

/// 幣價：Binance 公開 24hr ticker（對 USDT，免 key）。
/// TWD 計價 = USDT 價 × MAX 交易所 USDT/TWD 即時匯率（Binance 沒有 TWD 交易對）。
/// 漲跌基準用 24 小時前價格（openPrice）——幣市 24/7 沒有「昨收」；
/// TWD 模式兩端乘同一匯率，漲跌 % 只反映幣價本身。
/// 匯率每輪都抓（不論顯示幣別），台幣損益一律用它算。
enum CryptoClient {

    static func fetchMany(_ symbols: [SymbolConfig], currency: CryptoCurrency,
                          completion: @escaping ([String: Quote]) -> Void) {
        guard !symbols.isEmpty else { completion([:]); return }
        let group = DispatchGroup()
        let lock = NSLock()
        var usdt: [String: (last: Double, open: Double)] = [:]
        var twdRate: Double?

        // 逐檔查：Binance 批次查詢只要有一個代號無效就整批 400，分開查才不會一錯全掛。
        for sym in symbols {
            group.enter()
            fetchTicker(sym.code) { t in
                if let t = t { lock.lock(); usdt[sym.code] = t; lock.unlock() }
                group.leave()
            }
        }
        group.enter()
        fetchUSDTTWD { r in
            lock.lock(); twdRate = r; lock.unlock()
            group.leave()
        }
        group.notify(queue: .global()) {
            // TWD 顯示但匯率抓不到：整批不回，避免把 USDT 數字當 TWD 顯示
            let rate: Double
            switch currency {
            case .usdt: rate = 1
            case .twd:
                guard let r = twdRate else { completion([:]); return }
                rate = r
            }
            var out: [String: Quote] = [:]
            for (code, t) in usdt {
                out[code] = Quote(code: code, name: "\(code)/\(currency.rawValue)",
                                  price: t.last * rate, prevClose: t.open * rate,
                                  time: "", isLive: true, unit: currency.rawValue, usdPrice: t.last,
                                  twdPrice: twdRate.map { t.last * $0 })
            }
            completion(out)
        }
    }

    private static func fetchTicker(_ code: String,
                                    completion: @escaping ((last: Double, open: Double)?) -> Void) {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbol=\(code.uppercased())USDT") else {
            completion(nil); return
        }
        getJSON(url) { m in
            guard let last = Double(m?["lastPrice"] as? String ?? ""), last > 0 else { completion(nil); return }
            completion((last, Double(m?["openPrice"] as? String ?? "") ?? 0))
        }
    }

    private static func fetchUSDTTWD(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://max-api.maicoin.com/api/v2/tickers/usdttwd") else {
            completion(nil); return
        }
        getJSON(url) { m in
            guard let r = Double(m?["last"] as? String ?? ""), r > 0 else { completion(nil); return }
            completion(r)
        }
    }

    private static func getJSON(_ url: URL, completion: @escaping ([String: Any]?) -> Void) {
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 8)) { data, _, _ in
            completion(data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        }.resume()
    }
}
