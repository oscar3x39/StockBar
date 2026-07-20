# StockBar

A macOS menu-bar app showing live Taiwan stock prices, delayed by under 1 minute. Track any listed (TSE) or over-the-counter (OTC) symbol, with multi-symbol switching.

- Pure Swift + SwiftPM, **no Xcode required**: `swift build -c release`
- Data source: TWSE official real-time quote API (no key)
- Refreshes every 15s during market hours, backs off to 5 min after close
- Taiwan color convention: red = up, green = down
- Falls back to best bid/ask or previous close when there's no trade (after hours)
- The menu bar shows only price + change; the dropdown manages multiple symbols

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

The config lives at `~/.config/StockBar/config.json`, created on first launch. Edit it via the **Open Config…** menu item, or directly:

```json
{
  "symbols" : [
    { "code" : "0050", "market" : "tse" },
    { "code" : "2330", "market" : "tse" },
    { "code" : "6488", "market" : "otc" }
  ],
  "refreshSeconds" : 15,
  "activeIndex" : 0
}
```

- `market`: `tse` for listed (default, omittable), `otc` for over-the-counter
- `activeIndex`: which symbol (0-based) shows in the menu-bar title
- Saved changes apply on the next poll — no restart needed

You can also manage symbols straight from the dropdown: **Add Symbol…** (enter a code, tick OTC), **Remove Symbol**, click any symbol to switch the menu-bar display, and **Launch at Login**.

## Build .app / cut a Release

```
Scripts/build-app.sh 1.0.0
```

Produces `dist/StockBar.app` and `dist/StockBar-1.0.0.zip` (ad-hoc signed, not notarized).
