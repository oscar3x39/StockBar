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

    static func fetch(_ code: String, completion: @escaping (Result<Quote, Error>) -> Void) {
        // ex_ch 上市用 tse_、上櫃用 otc_。0050 是上市。
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let urlStr = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=tse_\(code).tw&json=1&_=\(ts)"
        guard let url = URL(string: urlStr) else { completion(.failure(QuoteError.network)); return }

        var req = URLRequest(url: url, timeoutInterval: 8)
        // mis 端偶爾對無 Referer / UA 的請求給空 msgArray，補齊避免被擋
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.setValue("https://mis.twse.com.tw/stock/fibest.jsp", forHTTPHeaderField: "Referer")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, err in
            if err != nil { completion(.failure(QuoteError.network)); return }
            guard let data = data else { completion(.failure(QuoteError.noData)); return }
            guard let quote = parse(data, fallbackCode: code) else {
                completion(.failure(QuoteError.badPayload)); return
            }
            completion(.success(quote))
        }.resume()
    }

    private static func parse(_ data: Data, fallbackCode: String) -> Quote? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["msgArray"] as? [[String: Any]],
              let m = arr.first else { return nil }

        let code = (m["c"] as? String) ?? fallbackCode
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
