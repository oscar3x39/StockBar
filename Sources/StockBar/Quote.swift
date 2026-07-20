import Foundation

/// 一筆即時報價（已解析、可直接顯示）
struct Quote {
    let code: String        // 0050
    let name: String        // 元大台灣50
    let price: Double       // 現價（成交 or fallback）
    let prevClose: Double   // 昨收
    let time: String        // 撮合時間 HH:mm:ss（或空）
    let isLive: Bool        // true=有成交價, false=用 fallback（盤後/無量）

    var change: Double { price - prevClose }
    var changePct: Double { prevClose == 0 ? 0 : change / prevClose * 100 }
}

enum QuoteError: Error { case network, badPayload, noData }

/// TWSE 官方即時揭示 API（免 key、盤中約 5–20s 更新一次）
enum TWSEClient {

    /// 一次查多檔（ex_ch 用 | 串接），回傳以 code 為 key 的字典。
    /// 單次 request 省流量、也避免多檔各自 rate limit。
    static func fetchMany(_ symbols: [SymbolConfig],
                          completion: @escaping ([String: Quote]) -> Void) {
        guard !symbols.isEmpty else { completion([:]); return }
        let exch = symbols.map { $0.exCh }.joined(separator: "|")
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let urlStr = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=\(exch)&json=1&_=\(ts)"
        guard let url = URL(string: urlStr) else { completion([:]); return }

        var req = URLRequest(url: url, timeoutInterval: 8)
        // mis 端偶爾對無 Referer / UA 的請求給空 msgArray，補齊避免被擋
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.setValue("https://mis.twse.com.tw/stock/fibest.jsp", forHTTPHeaderField: "Referer")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["msgArray"] as? [[String: Any]] else {
                completion([:]); return
            }
            var out: [String: Quote] = [:]
            for m in arr {
                if let q = parse(m) { out[q.code] = q }
            }
            completion(out)
        }.resume()
    }

    private static func parse(_ m: [String: Any]) -> Quote? {
        guard let code = m["c"] as? String else { return nil }
        let name = (m["n"] as? String) ?? code
        let prevClose = num(m["y"])            // 昨收
        let time = (m["t"] as? String) ?? ""

        // 現價優先序：成交價 z → 最佳買價 b → 最佳賣價 a → 昨收
        let z = num(m["z"])                    // "-" 會被 num 轉成 0
        if z > 0 {
            return Quote(code: code, name: name, price: z, prevClose: prevClose, time: time, isLive: true)
        }
        let bid = firstOfList(m["b"])          // "195.10_195.05_..." 取第一檔
        let ask = firstOfList(m["a"])
        let fallback = bid > 0 ? bid : (ask > 0 ? ask : prevClose)
        return Quote(code: code, name: name, price: fallback, prevClose: prevClose, time: time, isLive: false)
    }

    /// TWSE 欄位是字串，"-" / "" 視為 0
    private static func num(_ v: Any?) -> Double {
        guard let s = v as? String, let d = Double(s) else { return 0 }
        return d
    }

    /// 買賣五檔是 "p1_p2_p3_..." 用底線分隔，取第一個有效價
    private static func firstOfList(_ v: Any?) -> Double {
        guard let s = v as? String else { return 0 }
        for part in s.split(separator: "_") {
            if let d = Double(part) { return d }
        }
        return 0
    }
}
