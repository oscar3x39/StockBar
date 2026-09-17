import SwiftUI

// MARK: - Style（版面比照 ClaudeBar；底色改中性灰，紅綠漲跌字才看得清楚）
enum Style {
    static let width: CGFloat = 360
    static let pad: CGFloat = 16
    static let bg = Color(white: 0.945)
    static let ink = Color(white: 0.13)
    static let sub = Color(white: 0.42)
    static let border = Color.black.opacity(0.18)
    // 台股習慣：紅漲綠跌
    static let up = Color(red: 0.86, green: 0.18, blue: 0.20)
    static let down = Color(red: 0.12, green: 0.62, blue: 0.32)

    static func tint(_ v: Double) -> Color { v > 0 ? up : (v < 0 ? down : ink) }

    static var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.95))
            .shadow(color: Color.black.opacity(0.07), radius: 4, y: 1)
    }
}

private extension View {
    func rowPadding() -> some View { padding(.horizontal, 12).frame(minHeight: 40) }
}

private func sectionView<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 11, weight: .bold)).foregroundColor(Style.sub)
            .tracking(0.6).padding(.leading, 4)
        VStack(spacing: 0) { content() }
            .background(Style.card)
            // 列的選取底色不能蓋出卡片圓角
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private var rowDivider: some View {
    Divider().overlay(Color.black.opacity(0.06)).padding(.leading, 12)
}

private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium)).foregroundColor(Style.ink)
            .frame(width: 26, height: 26)
            .background(Circle().stroke(Style.border, lineWidth: 1))
            .contentShape(Circle())
    }.buttonStyle(.plain).help(help)
}

private func pctBadge(_ pct: Double) -> some View {
    Text(Fmt.pct(pct))
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
        .foregroundColor(.white)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(pct == 0 ? Style.sub : Style.tint(pct)))
}

// MARK: - 面板暫存狀態
// 不用 @State：Command Line Tools 沒有 SwiftUIMacros 外掛，新版 SDK 的 @State 是 macro 會編不過。
// 改用 ObservableObject（@Published 不依賴該外掛），每次開面板重建一份。

struct HoldingDraft: Identifiable {
    let code: String
    var amount: String
    var cost: String
    var inUSD: Bool
    var id: String { code }
}

final class PanelState: ObservableObject {
    @Published var showingSettings = false
    @Published var newCode = ""
    @Published var newMarket = "tse"
    @Published var addError: String?
    @Published var drafts: [HoldingDraft] = []
    @Published var holdingNote: String?
    @Published var holdingError: String?
    @Published var updateNote: String?
}

// MARK: - Root

struct PopoverView: View {
    @ObservedObject var store: QuoteStore
    @ObservedObject var ui: PanelState
    let onQuit: () -> Void

    var body: some View {
        Group {
            if ui.showingSettings {
                SettingsPanel(store: store, ui: ui, onQuit: onQuit) { ui.showingSettings = false }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                MainPanel(store: store) { ui.showingSettings = true }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(Style.pad)
        .frame(width: Style.width)
        .background(Style.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.18), value: ui.showingSettings)
    }
}

// MARK: - Main

private struct MainPanel: View {
    @ObservedObject var store: QuoteStore
    let onSettings: () -> Void
    private var L: L10n { store.L }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            if store.hasHoldings { holdingsCard }
            watchlist
            Divider().overlay(Color.black.opacity(0.1))
            footer
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("StockBar").font(.system(size: 15.5, weight: .semibold)).foregroundColor(Style.ink)
            let open = TradingCalendar.isOpen(Date())
            Text(open ? L.t("TW market open", "台股盤中") : L.t("TW market closed", "台股收盤"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(open ? Style.up : Style.sub)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.06)))
            Spacer()
            // 隱私模式：工作場合一鍵遮住金額，只留 %
            Button { store.togglePrivacy() } label: {
                Image(systemName: store.privacy ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 15)).foregroundColor(store.privacy ? Style.ink : Style.sub)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.privacy ? L.t("Show amounts", "顯示金額") : L.t("Hide amounts", "隱藏金額"))
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16)).foregroundColor(Style.sub)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).help(L.t("Settings", "設定"))
        }
    }

    /// 台幣未實現損益總覽；點一下切換「是否顯示在 menu bar」
    private var holdingsCard: some View {
        Button { store.setShowHoldings(!store.showingHoldings) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("P&L (TWD)", "台幣損益"))
                        .font(.system(size: 11, weight: .bold)).foregroundColor(Style.sub).tracking(0.6)
                    Spacer()
                    menuBarMark(store.showingHoldings)
                }
                if let t = store.holdingsTotal {
                    // 今日 / 累計並排；今日放左邊，是最常看的
                    HStack(alignment: .top, spacing: 12) {
                        pnlBlock(store.periodLabel,
                                 store.periodTotal?.pnl, store.periodTotal?.pct,
                                 inMenuBar: store.showingHoldings && store.config.menuBarToday)
                        pnlBlock(L.t("Total", "累計"), t.pnl, t.pct,
                                 inMenuBar: store.showingHoldings && !store.config.menuBarToday)
                    }
                    if !store.privacy {
                        HStack(spacing: 14) {
                            stat(L.t("Value", "市值"), Fmt.money(t.value))
                            stat(L.t("Cost", "成本"), Fmt.money(t.cost))
                        }
                    }
                    excludedNote
                } else {
                    Text(L.t("Waiting for prices…", "等待報價中…"))
                        .font(.system(size: 13)).foregroundColor(Style.sub)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L.t("Click to show in the menu bar", "點一下顯示在選單列"))
    }

    /// 一格損益：標題、金額（隱私模式改顯示 %）、% 徽章
    private func pnlBlock(_ title: String, _ pnl: Double?, _ pct: Double?, inMenuBar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Style.sub)
                if inMenuBar {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 10)).foregroundColor(Style.ink)
                        .help(L.t("Shown in the menu bar", "顯示在選單列"))
                }
            }
            if let pnl = pnl, let pct = pct {
                if store.privacy {
                    Text(Fmt.pct(pct))
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundColor(Style.tint(pnl))
                } else {
                    Text(Fmt.signedMoney(pnl))
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundColor(Style.tint(pnl))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    pctBadge(pct)
                }
            } else {
                Text("—").font(.system(size: 24, weight: .bold)).foregroundColor(Style.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var excludedNote: some View {
        if store.todayIncludesCrypto {
            Text(L.t("Crypto 'today' = last 24h.", "幣的「今日」為 24 小時漲跌。"))
                .font(.system(size: 11)).foregroundColor(Style.sub)
        }
        let codes = store.excludedCodes
        if !codes.isEmpty {
            Text(L.t("Not included: ", "未計入：") + codes.joined(separator: ", "))
                .font(.system(size: 11)).foregroundColor(Style.sub)
        }
        if store.privacy {
            Label(L.t("Amounts hidden", "金額已隱藏"), systemImage: "eye.slash")
                .font(.system(size: 11)).foregroundColor(Style.sub)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundColor(Style.sub)
            Text(value).font(.system(size: 12.5, weight: .medium).monospacedDigit()).foregroundColor(Style.ink)
        }
    }

    /// 目前顯示在 menu bar 的那一項
    @ViewBuilder
    private func menuBarMark(_ on: Bool) -> some View {
        if on {
            Label(L.t("Menu bar", "選單列"), systemImage: "menubar.rectangle")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(Style.ink)
                .labelStyle(.titleAndIcon)
        } else {
            Text(L.t("Click to show in menu bar", "點一下顯示在選單列"))
                .font(.system(size: 10.5)).foregroundColor(Style.sub.opacity(0.8))
        }
    }

    private var watchlist: some View {
        sectionView(L.t("WATCHLIST", "自選")) {
            ForEach(Array(store.visibleSymbols.enumerated()), id: \.element.code) { i, sym in
                if i > 0 { rowDivider }
                row(sym)
            }
            if store.hiddenCount > 0 {
                if !store.visibleSymbols.isEmpty { rowDivider }
                Label(L.t("\(store.hiddenCount) hidden", "已隱藏 \(store.hiddenCount) 檔"), systemImage: "eye.slash")
                    .font(.system(size: 11.5)).foregroundColor(Style.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    private func row(_ sym: SymbolConfig) -> some View {
        let q = store.quotes[sym.code]
        let selected = !store.showingHoldings && store.activeSymbol?.code == sym.code
        return Button { store.select(sym.code) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sym.isTW ? (q?.name ?? sym.code) : sym.code)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Style.ink)
                        .lineLimit(1)
                    Text(sym.isCrypto ? (q?.unit ?? store.config.currency.rawValue) : (sym.isUS ? "USD" : sym.code))
                        .font(.system(size: 11)).foregroundColor(Style.sub)
                    if selected {
                        Image(systemName: "menubar.rectangle")
                            .font(.system(size: 11)).foregroundColor(Style.ink)
                            .help(L.t("Shown in the menu bar", "顯示在選單列"))
                    }
                    Spacer(minLength: 6)
                    if let q = q {
                        Text(Fmt.price(q.price))
                            .font(.system(size: 14, weight: .medium).monospacedDigit())
                            .foregroundColor(Style.ink)
                        Text(Fmt.pct(q.changePct))
                            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                            .foregroundColor(Style.tint(q.change))
                            .frame(minWidth: 62, alignment: .trailing)
                    } else {
                        Text(L.t("Loading…", "載入中…")).font(.system(size: 12)).foregroundColor(Style.sub)
                    }
                }
                subline(sym, q)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(selected ? Color.black.opacity(0.035) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func subline(_ sym: SymbolConfig, _ q: Quote?) -> some View {
        if sym.amount != nil, store.privacy {
            // 隱私模式：只留累計報酬率（今日 % 已在上一行）
            if let h = store.holding(sym) {
                HStack(spacing: 6) {
                    Text(L.t("Total return", "累計報酬率"))
                    Spacer(minLength: 4)
                    if !sym.inTotal { excludedTag }
                    Text(Fmt.pct(h.pct))
                        .fontWeight(.semibold)
                        .foregroundColor(sym.inTotal ? Style.tint(h.pnl) : Style.sub)
                }
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundColor(Style.sub)
            }
        } else if let amt = sym.amount {
            // 不計入總損益的用灰色，避免跟總數混在一起看
            let tint = { (v: Double) in sym.inTotal ? Style.tint(v) : Style.sub }
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text("× \(Fmt.amount(amt))")
                    if let h = store.holding(sym) { Text("≈ \(Fmt.money(h.value)) TWD") }
                    Spacer(minLength: 4)
                    if let d = store.periodPnL(sym) {
                        Text(store.periodLabel)
                        Text(Fmt.signedMoney(d)).fontWeight(.semibold).foregroundColor(tint(d))
                    }
                }
                if let h = store.holding(sym) {
                    HStack(spacing: 6) {
                        Text(L.t("Total", "累計"))
                        Spacer(minLength: 4)
                        if !sym.inTotal { excludedTag }
                        Text("\(Fmt.signedMoney(h.pnl)) (\(Fmt.pct(h.pct)))")
                            .fontWeight(.semibold).foregroundColor(tint(h.pnl))
                    }
                }
            }
            .font(.system(size: 11.5).monospacedDigit())
            .foregroundColor(Style.sub)
        } else if let q = q, !q.isLive {
            // 沒有成交價時 TWSEClient 用買賣價 / 昨收代替；盤中多半只是這一刻沒撮合
            Text((sym.isUS ? TradingCalendar.isUSOpen(Date()) : TradingCalendar.isOpen(Date()))
                 ? L.t("No trade yet · bid/ask", "暫無成交 · 參考買賣價")
                 : L.t("Closed · last price", "收盤 · 最後價格"))
                .font(.system(size: 11)).foregroundColor(Style.sub)
        } else if sym.isCrypto {
            Text(L.t("24h change", "24 小時漲跌"))
                .font(.system(size: 11)).foregroundColor(Style.sub)
        }
    }

    private var excludedTag: some View {
        Text(L.t("excluded", "不計入"))
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.black.opacity(0.07)))
    }

    /// 固定 24 小時制，不跟系統語系出現「上午」
    private static func formatter(_ format: String, _ tz: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = format
        return f
    }
    private static let twClock = formatter("HH:mm:ss", "Asia/Taipei")
    private static let twDay = formatter("MM/dd", "Asia/Taipei")
    private static let usDay = formatter("MM/dd", "America/New_York")
    private static let localClock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// 各市場資料時間：盤中顯示時間，收盤顯示「哪天收盤」，不再用抓取時間冒充即時
    private var dataTimes: String {
        let now = Date()
        func latest(_ pick: (SymbolConfig) -> Bool) -> Date? {
            store.visibleSymbols.filter(pick).compactMap { store.quotes[$0.code]?.asOf }.max()
        }
        var parts: [String] = []
        if let d = latest({ $0.isTW }) {
            let open = store.isOpen(.tw, now)
            let today = Self.twDay.string(from: d) == Self.twDay.string(from: now)
            parts.append(open ? L.t("TW ", "台股 ") + Self.twClock.string(from: d)
                         // 收盤只標哪天：上櫃盤後定價等時段的時間戳會晚於 13:30，列時間反而誤導
                         : L.t("TW ", "台股 ") + (today ? L.t("closed today", "今日收盤")
                                                     : Self.twDay.string(from: d) + L.t(" close", " 收盤")))
        }
        if let d = latest({ $0.isUS }) {
            parts.append(store.isOpen(.us, now)
                         ? L.t("US ", "美股 ") + Self.localClock.string(from: d)
                         : L.t("US ", "美股 ") + Self.usDay.string(from: d) + L.t(" close", " 收盤"))
        }
        if let d = latest({ $0.isCrypto }) {
            parts.append(L.t("Crypto ", "幣 ") + Self.localClock.string(from: d))
        }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack {
            Text(dataTimes)
                .font(.system(size: 11.5).monospacedDigit()).foregroundColor(Style.sub)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            iconButton("arrow.clockwise", help: L.t("Refresh", "重新整理")) { store.refresh(force: true) }
        }
    }
}

// MARK: - Settings

private struct SettingsPanel: View {
    @ObservedObject var store: QuoteStore
    @ObservedObject var ui: PanelState
    let onQuit: () -> Void
    let onBack: () -> Void
    private var L: L10n { store.L }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Style.ink)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                        .contentShape(Circle())
                }.buttonStyle(.plain).help(L.t("Back", "返回"))
                Text(L.t("Settings", "設定")).font(.system(size: 17, weight: .semibold)).foregroundColor(Style.ink)
                Spacer()
            }

            watchlistSection
            if store.privacy {
                // 隱私模式下不攤開數量與成本
                sectionView(L.t("HOLDINGS", "持倉")) {
                    Label(L.t("Hidden in privacy mode. Tap the eye on the main page to edit.",
                              "隱私模式中不顯示。回主畫面點眼睛關閉後即可編輯。"),
                          systemImage: "eye.slash")
                        .font(.system(size: 12)).foregroundColor(Style.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            } else if !ui.drafts.isEmpty {
                holdingsSection
            }
            displaySection
            generalSection

            Button(action: onQuit) {
                HStack(spacing: 10) {
                    Image(systemName: "power").frame(width: 18)
                    Text(L.t("Quit StockBar", "結束 StockBar"))
                    Spacer()
                }
                .font(.system(size: 14)).foregroundColor(.red)
                .rowPadding().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Style.card)
        }
        .onAppear(perform: loadDrafts)
        .onChange(of: store.config.symbols.map(\.code)) { _ in loadDrafts() }
    }

    /// 從設定載入持倉草稿；已經在編輯的欄位保留
    private func loadDrafts() {
        let old = Dictionary(uniqueKeysWithValues: ui.drafts.map { ($0.code, $0) })
        ui.drafts = store.config.symbols.map { sym in
            old[sym.code] ?? HoldingDraft(code: sym.code,
                                          amount: sym.amount.map(Fmt.plain) ?? "",
                                          cost: (sym.costInUSD ? sym.costUSD : sym.costTWD).map(Fmt.plainCost) ?? "",
                                          inUSD: sym.costInUSD)
        }
    }

    // MARK: sections

    private var watchlistSection: some View {
        sectionView(L.t("WATCHLIST", "自選清單")) {
            ForEach(Array(store.config.symbols.enumerated()), id: \.element.code) { i, sym in
                if i > 0 { rowDivider }
                HStack(spacing: 8) {
                    Text(sym.code).font(.system(size: 14, weight: .medium)).foregroundColor(Style.ink)
                    Text(marketName(sym)).font(.system(size: 11.5)).foregroundColor(Style.sub)
                    Spacer()
                    let hidden = sym.hideInPrivacy ?? false
                    Button { store.setHideInPrivacy(sym.code, !hidden) } label: {
                        Image(systemName: hidden ? "eye.slash" : "eye")
                            .font(.system(size: 14)).foregroundColor(hidden ? Style.ink : Style.sub.opacity(0.6))
                            .frame(width: 22)
                    }
                    .buttonStyle(.plain)
                    .help(hidden ? L.t("Hidden in privacy mode", "隱私模式時隱藏")
                                 : L.t("Hide this in privacy mode", "隱私模式時隱藏這檔"))
                    Button { store.removeSymbol(sym.code) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16)).foregroundColor(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.config.symbols.count <= 1)
                    .help(L.t("Remove", "移除"))
                }.rowPadding()
            }
            rowDivider
            HStack(spacing: 8) {
                TextField(L.t("2330 / VOO / ETH", "代號 2330 / VOO / ETH"), text: $ui.newCode)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13))
                    .onSubmit(add)
                Picker("", selection: $ui.newMarket) {
                    Text(L.t("Listed", "上市")).tag("tse")
                    Text(L.t("OTC", "上櫃")).tag("otc")
                    Text(L.t("US", "美股")).tag("us")
                    Text(L.t("Crypto", "加密貨幣")).tag("crypto")
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18)).foregroundColor(Style.ink)
                }.buttonStyle(.plain).help(L.t("Add", "新增"))
            }.rowPadding().padding(.vertical, 4)
            if let e = ui.addError {
                Text(e).font(.system(size: 11.5)).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }

    private func marketName(_ sym: SymbolConfig) -> String {
        if sym.isCrypto { return L.t("Crypto", "加密貨幣") }
        if sym.isUS { return L.t("US", "美股") }
        return sym.ex == "otc" ? L.t("OTC", "上櫃") : L.t("Listed", "上市")
    }

    private func add() {
        ui.addError = store.addSymbol(ui.newCode, market: ui.newMarket)
        if ui.addError == nil { ui.newCode = "" }
    }

    private var holdingsSection: some View {
        sectionView(L.t("HOLDINGS", "持倉")) {
            ForEach(Array($ui.drafts.enumerated()), id: \.element.id) { i, $d in
                if i > 0 { rowDivider }
                holdingRow($d)
            }
            rowDivider
            HStack(alignment: .top, spacing: 8) {
                Text(ui.holdingError ?? ui.holdingNote ?? holdingsHint)
                    .font(.system(size: 11))
                    .foregroundColor(ui.holdingError != nil ? .red : Style.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(L.t("Save", "儲存"), action: saveHoldings)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private var holdingsHint: String {
        L.t("""
            ☑ = include in total (applies at once).
            Taiwan stocks: shares, not lots (1 lot = 1000).
            Cost is per share / coin; empty = current price.
            USD cost: return % follows the USD price, like your broker.
            """, """
            ☑＝計入總損益（勾了立即生效）。
            台股填股數，不是張數（1 張 = 1000 股）。
            成本是每股 / 每顆的價格，留空＝用現價。
            成本選美元：報酬率只看美元股價，和券商一致。
            """)
    }

    private static let fieldWidth: CGFloat = 96
    private static let trailingWidth: CGFloat = 74

    /// 一檔兩行：[計入] 代號 … 數量 [   ] 股 / 成本 [   ] [幣別]
    private func holdingRow(_ d: Binding<HoldingDraft>) -> some View {
        let code = d.wrappedValue.code
        let sym = store.config.symbols.first { $0.code == code }
        let isTW = sym?.isTW ?? true
        let usdLabel = (sym?.isCrypto ?? false) ? "USDT" : "USD"
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                // 勾選即存，不必按儲存
                Toggle("", isOn: Binding(get: { sym?.inTotal ?? true }, set: { store.setInTotal(code, $0) }))
                    .labelsHidden().toggleStyle(.checkbox)
                    .help(L.t("Include in total P&L", "計入總損益"))
                Text(code).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Style.ink)
                    .lineLimit(1).fixedSize()   // 代號不讓位給輸入框
                Spacer(minLength: 4)
                Text(L.t("Qty", "數量")).font(.system(size: 11.5)).foregroundColor(Style.sub).fixedSize()
                TextField("—", text: d.amount).textFieldStyle(.roundedBorder)
                    .frame(width: Self.fieldWidth)
                // 台股價格是每股（1 張 = 1000 股），所以數量一律填股數
                Text(unitName(sym))
                    .font(.system(size: 11.5)).foregroundColor(Style.sub)
                    .frame(width: Self.trailingWidth, alignment: .leading)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 4)
                Text(L.t("Cost", "成本")).font(.system(size: 11.5)).foregroundColor(Style.sub).fixedSize()
                TextField(L.t("empty = now", "空白 = 現價"), text: d.cost).textFieldStyle(.roundedBorder)
                    .frame(width: Self.fieldWidth)
                Group {
                    if isTW {
                        Text("TWD").font(.system(size: 11.5)).foregroundColor(Style.sub)
                    } else {
                        Picker("", selection: d.inUSD) {
                            Text("TWD").tag(false)
                            Text(usdLabel).tag(true)
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                        .help(L.t("Currency of the cost you enter", "成本用哪種幣別填"))
                    }
                }
                .frame(width: Self.trailingWidth, alignment: .leading)
            }
        }
        .font(.system(size: 13).monospacedDigit())
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func unitName(_ sym: SymbolConfig?) -> String {
        (sym?.isCrypto ?? false) ? L.t("coins", "顆") : L.t("shares", "股")
    }

    private func saveHoldings() {
        ui.holdingNote = nil
        for d in ui.drafts {
            if let e = store.saveHolding(code: d.code, amount: d.amount, cost: d.cost, inUSD: d.inUSD) {
                ui.holdingError = e
                return
            }
        }
        ui.holdingError = nil
        // 以存檔後的值回填（例如成本空白被補成現價）
        ui.drafts = []
        loadDrafts()
        ui.holdingNote = L.t("Saved.", "已儲存。")
    }

    private var displaySection: some View {
        sectionView(L.t("DISPLAY", "顯示")) {
            HStack {
                Text(L.t("Language", "語言")).font(.system(size: 14)).foregroundColor(Style.ink)
                Spacer()
                Picker("", selection: Binding(get: { store.config.lang }, set: { store.setLanguage($0) })) {
                    Text("English").tag(AppLanguage.en)
                    Text("中文").tag(AppLanguage.zh)
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }.rowPadding()
            rowDivider
            HStack {
                Text(L.t("Crypto price in", "幣價顯示")).font(.system(size: 14)).foregroundColor(Style.ink)
                Spacer()
                Picker("", selection: Binding(get: { store.config.currency }, set: { store.setCurrency($0) })) {
                    ForEach(CryptoCurrency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }.rowPadding()
            rowDivider
            // 期間損益：1 = 今日，最多 30 天
            HStack {
                Text(L.t("P&L period", "損益期間")).font(.system(size: 14)).foregroundColor(Style.ink)
                Spacer()
                Text(store.config.days == 1 ? L.t("Today", "今日") : L.t("\(store.config.days) days", "近 \(store.config.days) 天"))
                    .font(.system(size: 13).monospacedDigit()).foregroundColor(Style.sub)
                Stepper("", value: Binding(get: { store.config.days }, set: { store.setPnLDays($0) }), in: 1...30)
                    .labelsHidden()
            }.rowPadding()
            rowDivider
            HStack {
                Text(L.t("Show P&L in menu bar", "選單列顯示損益")).font(.system(size: 14)).foregroundColor(Style.ink)
                Spacer()
                Toggle("", isOn: Binding(get: { store.showingHoldings }, set: { store.setShowHoldings($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(!store.hasHoldings)
            }.rowPadding()
            if store.showingHoldings {
                rowDivider
                HStack {
                    Text(L.t("Menu bar P&L", "選單列損益")).font(.system(size: 14)).foregroundColor(Style.ink)
                    Spacer()
                    Picker("", selection: Binding(get: { store.config.menuBarToday },
                                                  set: { store.setMenuBarToday($0) })) {
                        Text(store.periodLabel).tag(true)
                        Text(L.t("Total", "累計")).tag(false)
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                }.rowPadding()
            }
        }
    }

    private var generalSection: some View {
        sectionView(L.t("GENERAL", "一般")) {
            HStack {
                Text(L.t("Launch at Login", "開機時啟動")).font(.system(size: 14)).foregroundColor(Style.ink)
                Spacer()
                Toggle("", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }.rowPadding()
            rowDivider
            actionRow(L.t("Check for Updates", "檢查更新"),
                      trailing: ui.updateNote ?? "v\(Updater.currentVersion ?? "dev")") { checkUpdates() }
        }
    }

    private func actionRow(_ title: String, trailing: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 14)).foregroundColor(Style.ink)
                Spacer()
                if let t = trailing {
                    Text(t).font(.system(size: 12)).foregroundColor(Style.sub).lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Style.sub.opacity(0.7))
            }
            .rowPadding().contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    /// 只比對版本；有新版才開 release 頁（不下載，理由見 Updater.swift）
    private func checkUpdates() {
        ui.updateNote = L.t("Checking…", "檢查中…")
        Updater.check { result in
            switch result {
            case .available(let latest, _):
                ui.updateNote = L.t("v\(latest) available", "有新版 v\(latest)")
                NSWorkspace.shared.open(Updater.releasesPage)
            case .upToDate(let current):
                ui.updateNote = L.t("Up to date (v\(current))", "已是最新 v\(current)")
            case .failed:
                ui.updateNote = L.t("Check failed", "檢查失敗")
            }
        }
    }
}
