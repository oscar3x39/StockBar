# StockBar

A macOS menu-bar app showing live Taiwan stock prices (delayed by under 1 minute), US stock and crypto prices, with unrealized TWD P&L for your holdings. English / 中文 UI.

- Pure Swift + SwiftPM, **no Xcode required**: `swift build -c release`
- Data sources (no keys): TWSE real-time quotes; Yahoo Finance for US stocks and USD/TWD (unofficial, may rate-limit); Binance + MAX USDT/TWD for crypto
- Refreshes every 15s during market hours, backs off to 5 min after close
- Taiwan color convention: red = up, green = down
- Falls back to best bid/ask or previous close when there's no trade
- The menu bar shows one price + change (or total P&L); click it for a panel with the watchlist, holdings and settings

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

Menu-bar only — no Dock icon.

## Configuration (multiple symbols)

The config lives at `~/.config/StockBar/config.json`, created on first launch. Everything is editable in the panel's **Settings** (gear icon); advanced users can also edit the file directly:

```json
{
  "symbols" : [
    { "code" : "0050", "market" : "tse" },
    { "code" : "2330", "market" : "tse" },
    { "code" : "6488", "market" : "otc" },
    { "code" : "BTC", "market" : "crypto", "amount" : 0.05, "costTWD" : 2400000 }
  ],
  "cryptoCurrency" : "USDT",
  "refreshSeconds" : 15,
  "activeIndex" : 0
}
```

- `market`: `tse` for listed (default, omittable), `otc` for over-the-counter, `us` for US stocks / ETFs (`VOO`, `QQQ`…, polled only during US regular hours), `crypto` for a coin (Binance public API; `BTC`, `ETH`, `WBETH`…). Crypto change is vs. 24h ago, and crypto keeps polling while the Taiwan market is closed
- `cryptoCurrency`: `USDT` (default) or `TWD`. TWD converts the USDT price at the MAX exchange USDT/TWD rate. Also settable in Settings
- `amount` / `costTWD` (optional, any symbol): quantity held (shares or coins) and cost per unit in TWD (filled with the current TWD price if omitted). The panel then shows TWD value and unrealized TWD P&L per symbol plus a total card. Because cost is fixed in TWD, P&L for US stocks and crypto includes exchange-rate moves. Set both in Settings → Holdings
- `costCurrency` / `costUSD` (optional, US stocks and crypto): set `costCurrency` to `USD` to enter cost per unit in USD (USDT for crypto) instead of TWD. Return % then follows the USD price only, matching most brokers; value and P&L are still shown in TWD at the current rate. Pick it per holding in Settings → Holdings
- `excludeFromTotal` (optional): `true` keeps showing that symbol's own P&L but leaves it out of the total (untick **Sum** in Settings → Holdings)
- `menuBarShowsHoldings`: show total unrealized TWD P&L in the menu bar (toggle in Settings, or click the P&L card); click any symbol to switch back
- `activeIndex`: which symbol (0-based) shows in the menu-bar title
- Saved changes apply on the next poll — no restart needed

- `language`: `en` or `zh` (defaults to the system language). Also settable in Settings

In the panel: click any symbol to show it in the menu bar. In Settings: add / remove symbols (listed, OTC or crypto), edit holdings, switch language and crypto price currency, and toggle **Launch at Login**.

## Build .app / cut a Release

```
Scripts/build-app.sh 1.0.0
```

Produces `dist/StockBar.app` and `dist/StockBar-1.0.0.zip` (ad-hoc signed, not notarized).
