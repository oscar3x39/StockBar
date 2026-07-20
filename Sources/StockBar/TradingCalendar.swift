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
}
