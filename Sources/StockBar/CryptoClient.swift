import Foundation

/// 幣價：Binance 公開 24hr ticker（對 USDT，免 key）。
/// TWD 計價 = USDT 價 × MAX 交易所 USDT/TWD 即時匯率（Binance 沒有 TWD 交易對）。
/// 漲跌基準用 24 小時前價格（openPrice）——幣市 24/7 沒有「昨收」；
/// TWD 模式兩端乘同一匯率，漲跌 % 只反映幣價本身。
///
/// 流量：所有幣合成 1 個請求；匯率快取 60 秒。Binance 批次只要有一個代號無效就整批 400，
/// 此時退回逐檔查，並把無效代號記下 30 分鐘內不再查。
enum CryptoClient {
    private static let lock = NSLock()
    private static var rateCache: (value: Double, at: Date)?
    private static var invalidUntil: [String: Date] = [:]

    static func fetchMany(_ symbols: [SymbolConfig], currency: CryptoCurrency,
                          completion: @escaping ([String: Quote]) -> Void) {
        let now = Date()
        lock.lock()
        let codes = symbols.map { $0.code.uppercased() }.filter { (invalidUntil[$0] ?? .distantPast) < now }
        lock.unlock()
        guard !codes.isEmpty else { completion([:]); return }

        let group = DispatchGroup()
        var tickers: [String: Ticker] = [:]
        var twdRate: Double?

        group.enter()
        fetchBatch(codes) { batch in
            if let batch = batch {
                tickers = batch
                group.leave()
                return
            }
            // 批次失敗：逐檔查，找出無效代號
            let inner = DispatchGroup()
            let innerLock = NSLock()
            for code in codes {
                inner.enter()
                fetchBatch([code]) { one in
                    innerLock.lock()
                    if let t = one?[code] { tickers[code] = t }
                    innerLock.unlock()
                    if one == nil {
                        lock.lock(); invalidUntil[code] = Date().addingTimeInterval(30 * 60); lock.unlock()
                    }
                    inner.leave()
                }
            }
            inner.notify(queue: .global()) { group.leave() }
        }
        group.enter()
        usdtTWD { r in twdRate = r; group.leave() }

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
            for sym in symbols {
                guard let t = tickers[sym.code.uppercased()] else { continue }
                out[sym.code] = Quote(code: sym.code, name: "\(sym.code)/\(currency.rawValue)",
                                      price: t.last * rate, prevClose: t.open * rate,
                                      time: "", isLive: true, unit: currency.rawValue,
                                      usdPrice: t.last, twdPrice: twdRate.map { t.last * $0 },
                                      asOf: t.at)
            }
            completion(out)
        }
    }

    private struct Ticker { let last: Double; let open: Double; let at: Date }

    /// 一次查多檔；任何失敗（含無效代號）回 nil
    private static func fetchBatch(_ codes: [String], completion: @escaping ([String: Ticker]?) -> Void) {
        let list = "[" + codes.map { "\"\($0)USDT\"" }.joined(separator: ",") + "]"
        var comps = URLComponents(string: "https://api.binance.com/api/v3/ticker/24hr")!
        comps.queryItems = [URLQueryItem(name: "symbols", value: list)]
        guard let url = comps.url else { completion(nil); return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 8)) { data, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                completion(nil); return
            }
            var out: [String: Ticker] = [:]
            for m in arr {
                guard let pair = m["symbol"] as? String, pair.hasSuffix("USDT"),
                      let last = Double(m["lastPrice"] as? String ?? ""), last > 0 else { continue }
                let closeMs = (m["closeTime"] as? NSNumber)?.doubleValue
                out[String(pair.dropLast(4))] = Ticker(
                    last: last,
                    open: Double(m["openPrice"] as? String ?? "") ?? 0,
                    at: closeMs.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date())
            }
            completion(out)
        }.resume()
    }

    /// MAX USDT/TWD；匯率變動慢，60 秒內用快取
    private static func usdtTWD(completion: @escaping (Double?) -> Void) {
        lock.lock()
        if let c = rateCache, Date().timeIntervalSince(c.at) < 60 {
            lock.unlock(); completion(c.value); return
        }
        lock.unlock()
        guard let url = URL(string: "https://max-api.maicoin.com/api/v2/tickers/usdttwd") else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 8)) { data, _, _ in
            let m = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let r = Double(m?["last"] as? String ?? ""), r > 0 else {
                // 抓不到就沿用舊值（最多 10 分鐘），避免短暫失敗讓台幣數字消失
                lock.lock()
                let stale = rateCache.flatMap { Date().timeIntervalSince($0.at) < 600 ? $0.value : nil }
                lock.unlock()
                completion(stale); return
            }
            lock.lock(); rateCache = (r, Date()); lock.unlock()
            completion(r)
        }.resume()
    }
}
