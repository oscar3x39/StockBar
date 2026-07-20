# StockBar

macOS menu-bar app 顯示台股 0050（元大台灣50）即時價，時差 <1 分鐘。

- 純 Swift + SwiftPM，**不需 Xcode**：`swift build -c release`
- 資料源：TWSE 官方即時揭示 API（免 key）
- 盤中每 15s 更新、盤後拉長到 5 分鐘
- 台股配色：紅漲綠跌
- 無成交/盤後自動 fallback 到最佳買賣價或昨收

## 執行

```
swift build -c release
./.build/release/StockBar
```

menu-bar only，不進 Dock。點選單有現價／昨收／漲跌／狀態、立即更新、結束。

## 開機自動啟動（選用）

用 launchd 或「系統設定 → 一般 → 登入項目」加入 build 出來的執行檔即可。
