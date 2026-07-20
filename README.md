# StockBar

macOS menu-bar app 顯示台股即時價，時差 <1 分鐘。可自選任意上市／上櫃股票，支援多檔切換。

- 純 Swift + SwiftPM，**不需 Xcode**：`swift build -c release`
- 資料源：TWSE 官方即時揭示 API（免 key）
- 盤中每 15s 更新、盤後拉長到 5 分鐘
- 台股配色：紅漲綠跌
- 無成交/盤後自動 fallback 到最佳買賣價或昨收
- menu bar 只顯示價格＋漲跌，下拉選單管理多檔

## 安裝（下載版）

到 [Releases](https://github.com/oscar3x39/StockBar/releases) 下載 `StockBar-x.y.z.zip`，解壓後把 `StockBar.app` 拖到「應用程式」。

App 未經 Apple 公證，首次開啟會被 Gatekeeper 擋。放行方式二選一：

```bash
# 移除隔離屬性後直接開
xattr -dr com.apple.quarantine /Applications/StockBar.app
open /Applications/StockBar.app
```

或：在 Finder 對 `StockBar.app` 按右鍵 →「打開」→ 再按一次「打開」。

## 從原始碼執行

```
swift build -c release
./.build/release/StockBar
```

menu-bar only，不進 Dock。

## 設定（多檔）

設定檔在 `~/.config/StockBar/config.json`，首次啟動自動生成。可從下拉選單「開啟設定檔…」編輯，或直接改：

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

- `market`：上市 `tse`（預設，可省略）、上櫃 `otc`
- `activeIndex`：menu bar 標題顯示第幾檔（從 0 起算）
- 存檔後下一輪輪詢自動生效，不用重開

下拉選單也可直接操作：**新增標的…**（輸入代號、上櫃打勾）、**移除標的**、點任一檔切換 menu bar 顯示、**開機自動啟動**。

## 打包 .app / 出 Release

```
Scripts/build-app.sh 1.0.0
```

產出 `dist/StockBar.app` 與 `dist/StockBar-1.0.0.zip`（ad-hoc 簽章、未公證）。
