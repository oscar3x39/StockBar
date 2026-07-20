import Foundation

/// 開機自動啟動：透過使用者層級 launchd LaunchAgent 管理（不需 root）。
/// plist: ~/Library/LaunchAgents/com.oscar3x39.stockbar.plist
enum LaunchAgent {
    static let label = "com.oscar3x39.stockbar"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 目前執行檔的絕對路徑（rebuild 後路徑不變，plist 可持續指向）
    private static var execPath: String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func enable() {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [execPath],
            "RunAtLoad": true,          // 登入即啟動
            "KeepAlive": false,         // 使用者主動結束後不自動復活
        ]
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: plistURL)
        run(["load", "-w", plistURL.path])
    }

    static func disable() {
        run(["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}
