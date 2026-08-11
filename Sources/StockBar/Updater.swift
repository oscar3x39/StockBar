import AppKit

/// 「檢查更新」：只比對版本、只開瀏覽器，不下載、不改任何檔案。
/// 刻意不做自動下載替換——app 目前是 self-signed 未公證，
/// 自幹下載通道等於開一條無法驗證來源的寫入路徑。要無感更新請先做
/// notarization + Sparkle（EdDSA 簽章的 appcast），別走捷徑。
enum Updater {
    static let repo = "oscar3x39/StockBar"
    static var releasesPage: URL { URL(string: "https://github.com/\(repo)/releases/latest")! }

    /// 目前 bundle 版本；從 `swift run` 直接跑時沒有 Info.plist，回 nil（視為 dev build）
    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    enum Result {
        case upToDate(String)
        case available(latest: String, current: String)
        case failed
    }

    static func check(completion: @escaping (Result) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("StockBar", forHTTPHeaderField: "User-Agent")   // GitHub API 要求帶 UA

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else {
                DispatchQueue.main.async { completion(.failed) }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = currentVersion ?? "0.0.0"
            let result: Result = isNewer(latest, than: current)
                ? .available(latest: latest, current: current)
                : .upToDate(current)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// 數字逐段比大小（1.0.10 > 1.0.9），段數不同時缺的補 0
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
