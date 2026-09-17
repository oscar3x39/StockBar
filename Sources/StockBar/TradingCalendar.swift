import Foundation

/// 台股交易時段判斷（Asia/Taipei，週一~五 09:00–13:30）
/// 註：不含國定假日／颱風假，盤後 API 會回昨收，不影響正確性，只影響輪詢頻率。
enum TradingCalendar {
    static func isOpen(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        guard let tz = TimeZone(identifier: "Asia/Taipei") else { return true }
        cal.timeZone = tz
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, let h = c.hour, let m = c.minute else { return false }
        if wd == 1 || wd == 7 { return false }          // 週日=1、週六=7
        let mins = h * 60 + m
        return mins >= 9 * 60 && mins <= 13 * 60 + 30    // 09:00–13:30
    }

    enum Market { case tw, us }

    /// 最近一次（≤ now）平日收盤後 5 分鐘的時間點；用來判斷「收盤前抓的價格要補抓一次最終價」。
    /// 不含假日，假日只是多抓一次、不影響正確性。
    static func lastClose(_ market: Market, before now: Date) -> Date? {
        let (tzID, hour, minute) = market == .tw ? ("Asia/Taipei", 13, 35) : ("America/New_York", 16, 5)
        var cal = Calendar(identifier: .gregorian)
        guard let tz = TimeZone(identifier: tzID) else { return nil }
        cal.timeZone = tz
        for back in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: -back, to: now),
                  let close = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            let wd = cal.component(.weekday, from: close)
            if wd != 1 && wd != 7 && close <= now { return close }
        }
        return nil
    }

    /// 美股常規時段（America/New_York，週一~五 09:30–16:00，夏令時間由時區處理；不含美國假日）
    static func isUSOpen(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        guard let tz = TimeZone(identifier: "America/New_York") else { return true }
        cal.timeZone = tz
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, let h = c.hour, let m = c.minute else { return false }
        if wd == 1 || wd == 7 { return false }
        let mins = h * 60 + m
        return mins >= 9 * 60 + 30 && mins <= 16 * 60
    }
}
