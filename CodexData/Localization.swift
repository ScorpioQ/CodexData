import Foundation

enum AppText {
    nonisolated private static var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    nonisolated private static func localized(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }

    nonisolated static var connecting: String { localized("连接中", "Connecting") }
    nonisolated static var launchAtLogin: String { localized("开机启动", "Launch at Login") }
    nonisolated static var shortPercent: String { localized("5h百分比", "5h percent") }
    nonisolated static var longPercent: String { localized("7d百分比", "7d percent") }
    nonisolated static var shortCountdown: String { localized("5h倒计时", "5h countdown") }
    nonisolated static var longCountdown: String { localized("7d倒计时", "7d countdown") }
    nonisolated static var quit: String { localized("退出", "Quit") }
    nonisolated static var countdownAccessibility: String { localized("倒计时", "Countdown") }
    nonisolated static var codexPulseAccessibility: String { "Codex Pulse" }

    nonisolated static func statusTitle(for state: ConnectionState) -> String {
        localized("状态：\(state.label)", "Status: \(state.label)")
    }

    nonisolated static func connectionStateLabel(for state: ConnectionState) -> String {
        switch state {
        case .idle: localized("准备连接", "Ready")
        case .connecting: connecting
        case .live: localized("实时", "Live")
        case .failed: localized("离线", "Offline")
        }
    }

    nonisolated static var codexNotFound: String {
        localized(
            "找不到 Codex CLI，请先安装或启动 ChatGPT。",
            "Codex CLI was not found. Install or launch ChatGPT first."
        )
    }

    nonisolated static var invalidResponse: String {
        localized("Codex 返回了无法识别的数据。", "Codex returned unrecognized data.")
    }

    nonisolated static var processStopped: String {
        localized("Codex app-server 已停止。", "The Codex app-server has stopped.")
    }

    nonisolated static var requestFailed: String {
        localized("Codex 请求失败", "Codex request failed")
    }
}
