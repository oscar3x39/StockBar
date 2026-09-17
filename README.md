# StockBar

A macOS menu-bar app for Taiwan stocks, US stocks and crypto, with unrealized P&L for your holdings in TWD. English / 中文 UI.

- Pure Swift + SwiftPM, **no Xcode required**: `swift build -c release`
- No API keys, no account, no telemetry. Holdings stay on your Mac
- Taiwan color convention: red = up, green = down

## Features

**Menu bar**
- Shows one symbol's price and change, or your P&L (today / last N days, or total)
- Click it to open the panel

**Panel**
- P&L card: period P&L (today or last N days) next to total P&L, each with amount and %, plus market value and cost
- Watchlist: price and change for every symbol. For holdings, also quantity, TWD value, period P&L and total P&L
- Click a symbol (or the P&L card) to choose what the menu bar shows
- Data time per market at the bottom, e.g. `TW closed today · US 09/16 close · Crypto 15:07:06`
- Refresh button (forces a fetch of every market)

**Privacy mode** (eye icon)
- Hides quantities and money amounts everywhere, including the menu bar; only return % stays
- Per-symbol "hide in privacy mode" to drop a symbol from the panel entirely
- The holdings editor is hidden while privacy mode is on

**Settings** (gear icon)
- Watchlist: add / remove symbols (Taiwan listed, Taiwan OTC, US, crypto). Codes with no digits are rejected for Taiwan markets
- Holdings: quantity and unit cost per symbol; cost in TWD, or in USD / USDT for US stocks and crypto; tick whether each holding counts toward the total
- Display: language (English / 中文), crypto price in USDT or TWD, P&L period (1–30 days), whether the menu bar shows P&L and which one
- General: launch at login, check for updates (compares with the latest GitHub release and opens the release page; never downloads anything)
- Input accepts full-width digits (e.g. `０．０５`); invalid numbers show an error instead of being ignored

## Supported markets

| Market | `market` | Example codes | Price | "Today" means | Polled |
|---|---|---|---|---|---|
| Taiwan listed | `tse` | `0050`, `2330` | TWD per share | vs previous close | Mon–Fri 09:00–13:30 (Taipei) |
| Taiwan OTC | `otc` | `6488` | TWD per share | vs previous close | same as above |
| US stocks / ETFs | `us` | `VOO`, `QQQ` | USD per share | last session vs the one before | Mon–Fri 09:30–16:00 (New York) |
| Crypto | `crypto` | `BTC`, `ETH`, `WBETH` | USDT or TWD per coin | vs 24 hours ago | 24/7 |

Market hours ignore public holidays; on a holiday the app only makes a few extra requests, and prices are unaffected.

Taiwan quantities are in **shares**, not lots (1 lot = 1000 shares).

## How P&L is calculated

All amounts are in TWD.

| Figure | Formula |
|---|---|
| Market value | quantity × current price, converted to TWD at the current rate |
| Total P&L (cost in TWD) | value − quantity × TWD cost. Includes exchange-rate moves since you bought |
| Total P&L (cost in USD / USDT) | quantity × (price − USD cost), converted at the current rate. Return % follows the USD price only, like most brokers |
| Today | quantity × (price − previous close), converted at the current rate. Crypto uses the price 24h ago |
| Last N days | quantity × (price − last daily close on or before N calendar days ago), converted at the current rate |
| Total % | total P&L ÷ total cost |
| Period % | period P&L ÷ value at the start of the period |

- Empty cost = the current price when you save (P&L starts from that moment)
- Holdings with "count toward total" unticked still show their own P&L but are left out of the P&L card and the menu bar
- Period P&L excludes exchange-rate moves; total P&L with TWD cost includes them

## Data sources and API usage

All endpoints are public and need no key. Yahoo Finance endpoints are unofficial and may change or rate-limit; when a request fails, the last value stays on screen.

| Data | Endpoint | Requests |
|---|---|---|
| Taiwan quotes | TWSE `mis.twse.com.tw/stock/api/getStockInfo.jsp` | 1 request for all Taiwan symbols |
| US quotes + USD/TWD | Yahoo `query1.finance.yahoo.com/v8/finance/spark` | 1 request for all US symbols plus `TWD=X` |
| Crypto quotes | Binance `api.binance.com/api/v3/ticker/24hr?symbols=[…]` | 1 request for all coins |
| USDT/TWD | MAX `max-api.maicoin.com/api/v2/tickers/usdttwd` | cached 60 s |
| Daily closes (last N days) | Yahoo `v8/finance/chart` (`.TW` / `.TWO` / US), Binance `api/v3/klines` | 1 per holding, only when N > 1, cached 30 min |

Throttling and failure handling:

- **Open market**: Taiwan and crypto every `refreshSeconds` (default 15 s); US at most once a minute
- **Closed market**: fetched once after the close (5 min grace, to catch the final price), then at most every 30 min. Opening the panel does not refetch a closed market
- **Forced fetch** of every market: refresh button, wake from sleep, adding a symbol, switching the crypto price currency
- **When nothing is open**: the timer runs every 60 s and makes no requests unless something is due
- **Binance batch**: fails as a whole if any symbol is invalid. The app then queries each coin separately and skips invalid ones for 30 min
- **Retries**: a failed fetch for a closed market retries after 1 min; a failed daily-close fetch retries after 5 min
- **Rates**: if MAX fails, the last USDT/TWD rate is reused for up to 10 min. In TWD price mode with no rate, crypto is not updated rather than showing USDT numbers as TWD
- **No trade yet (Taiwan)**: the price falls back to the best bid, then best ask, then previous close, and the row says so

## Architecture

| File | Role |
|---|---|
| `main.swift` | AppKit shell: status item, menu-bar title, borderless panel hosting SwiftUI, hidden Edit menu (for ⌘C/⌘V in text fields) |
| `QuoteStore.swift` | State: config, quotes, per-market throttling, holdings and P&L math, all user actions |
| `PopoverView.swift` | SwiftUI panel: main page and settings page |
| `Quote.swift` | `Quote` model and the TWSE client |
| `USStockClient.swift` | Yahoo spark client (US quotes + USD/TWD) |
| `CryptoClient.swift` | Binance batch client, MAX rate cache, invalid-symbol skipping |
| `HistoryClient.swift` | Daily closes for N-day P&L |
| `TradingCalendar.swift` | Taiwan / US market hours and last close time |
| `Config.swift` | `config.json` model and load / save |
| `L10n.swift` | English / 中文 strings, number formatting and input parsing |
| `LaunchAgent.swift` | Launch at login via a user LaunchAgent |
| `Updater.swift` | Version check against the latest GitHub release |

Panel state uses an `ObservableObject` instead of SwiftUI `@State`: Command Line Tools ship without the SwiftUIMacros plugin, and `@State` is a macro in current SDKs, so it would not build without Xcode.

## Install (download)

Grab `StockBar-x.y.z.zip` from [Releases](https://github.com/oscar3x39/StockBar/releases), unzip it, and drag `StockBar.app` into `/Applications`.

The app is not notarized by Apple, so Gatekeeper blocks the first launch. Allow it either way:

```bash
# Remove the quarantine attribute, then open
xattr -dr com.apple.quarantine /Applications/StockBar.app
open /Applications/StockBar.app
```

Or: right-click `StockBar.app` in Finder → **Open** → **Open** again.

## Run from source

```
swift build -c release
./.build/release/StockBar
```

Menu-bar only — no Dock icon. Requires macOS 13 or later.

## Configuration

Everything is editable in the panel's Settings. The file is `~/.config/StockBar/config.json`, created on first launch; manual edits apply on the next poll, with no restart. Example (made-up numbers):

```json
{
  "symbols" : [
    { "code" : "0050", "market" : "tse", "amount" : 1000, "costTWD" : 100 },
    { "code" : "6488", "market" : "otc" },
    { "code" : "VOO", "market" : "us", "amount" : 2, "costUSD" : 600, "costCurrency" : "USD" },
    { "code" : "BTC", "market" : "crypto", "amount" : 0.01, "costTWD" : 2400000, "excludeFromTotal" : true }
  ],
  "activeIndex" : 0,
  "refreshSeconds" : 15,
  "cryptoCurrency" : "TWD",
  "language" : "zh",
  "pnlDays" : 7,
  "menuBarShowsHoldings" : true,
  "menuBarPnL" : "today",
  "privacyMode" : false
}
```

Per symbol:

| Key | Values | Meaning |
|---|---|---|
| `code` | string | Ticker. US and crypto codes are upper-cased |
| `market` | `tse` (default), `otc`, `us`, `crypto` | See [Supported markets](#supported-markets) |
| `amount` | number | Quantity held (shares / coins). Omit to track price only |
| `costTWD` | number | Cost per unit in TWD |
| `costUSD` | number | Cost per unit in USD (USDT for crypto); used when `costCurrency` is `USD` |
| `costCurrency` | `USD` or omitted | Omitted = TWD. Taiwan stocks are always TWD |
| `excludeFromTotal` | `true` or omitted | Show this holding's P&L but leave it out of the total |
| `hideInPrivacy` | `true` or omitted | Hide this symbol while privacy mode is on |

App-wide:

| Key | Values | Meaning |
|---|---|---|
| `activeIndex` | 0-based index | Symbol shown in the menu bar |
| `refreshSeconds` | ≥ 5, default 15 | Poll interval for open markets (US is at least 60) |
| `cryptoCurrency` | `USDT` (default), `TWD` | Currency for crypto prices |
| `language` | `en`, `zh` | Defaults to the system language |
| `pnlDays` | 1–30, default 1 | Period P&L: 1 = today |
| `menuBarShowsHoldings` | `true` / omitted | Menu bar shows P&L instead of a price |
| `menuBarPnL` | `today` (default), `total` | Which P&L the menu bar shows (`today` follows `pnlDays`) |
| `privacyMode` | `true` / omitted | Hide amounts, show only % |

## Build .app / cut a Release

```
Scripts/build-app.sh 1.2.0
```

Produces `dist/StockBar.app` and `dist/StockBar-1.2.0.zip`. It signs with the `StockBar Self-Signed` certificate if present (so macOS keeps treating rebuilds as the same app), otherwise ad-hoc. Not notarized.
