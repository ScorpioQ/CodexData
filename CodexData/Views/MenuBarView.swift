import AppKit
import Foundation

enum MenuBarFormatting {
    static func statusText(
        windows: [QuotaWindow],
        showShortPercent: Bool,
        showLongPercent: Bool,
        showShortCountdown: Bool,
        showLongCountdown: Bool,
        showSeconds: Bool,
        now: Date
    ) -> String? {
        let short = windows.first { $0.kind == .primary }
        let long = windows.first { $0.kind == .secondary }
        let shortText = segment(kind: .primary, for: short, showPercent: showShortPercent, showCountdown: showShortCountdown, showSeconds: showSeconds, now: now)
        let longText = segment(kind: .secondary, for: long, showPercent: showLongPercent, showCountdown: showLongCountdown, showSeconds: showSeconds, now: now)
        let segments = [shortText, longText].compactMap { $0 }
        return segments.isEmpty ? nil : segments.joined(separator: " - ")
    }

    static func percentText(kind: QuotaWindow.Kind, window: QuotaWindow?) -> String {
        let percent = window?.remainingPercent.map { "\(Int($0))%" } ?? "--"
        return "\(kind.title): \(percent)"
    }

    static func countdownText(kind: QuotaWindow.Kind, window: QuotaWindow?, showSeconds: Bool, now: Date) -> String {
        countdown(to: window?.resetDate, kind: kind, showSeconds: showSeconds, now: now)
    }

    static func attributedText(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let parts = text.components(separatedBy: "⏱")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        for (index, part) in parts.enumerated() {
            if !part.isEmpty {
                result.append(NSAttributedString(string: part, attributes: attributes))
            }
            guard index < parts.count - 1,
                  let symbol = NSImage(systemSymbolName: "clock", accessibilityDescription: AppText.countdownAccessibility) else { continue }

            let configured = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            ) ?? symbol
            configured.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = configured
            attachment.bounds = CGRect(x: 0, y: -2, width: font.pointSize, height: font.pointSize)
            result.append(NSAttributedString(attachment: attachment))
        }

        return result
    }

    private static func segment(kind: QuotaWindow.Kind, for window: QuotaWindow?, showPercent: Bool, showCountdown: Bool, showSeconds: Bool, now: Date) -> String? {
        guard showPercent || showCountdown else { return nil }
        var values: [String] = []
        if showPercent {
            let percent = window?.remainingPercent.map { "\(Int($0))%" } ?? "--"
            values.append(percent)
        }
        if showCountdown {
            values.append("⏱ \(countdown(to: window?.resetDate, kind: kind, showSeconds: showSeconds, now: now))")
        }
        return "\(kind.title): \(values.joined(separator: " "))"
    }

    private static func countdown(to date: Date?, kind: QuotaWindow.Kind, showSeconds: Bool, now: Date) -> String {
        guard let date else { return showSeconds ? "00:00:00" : "00:00" }
        let totalSeconds = max(0, Int(date.timeIntervalSince(now)))
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let totalHours = totalMinutes / 60

        guard showSeconds else {
            if kind == .secondary {
                let days = totalHours / 24
                return String(format: "%dd %02d:%02d", days, totalHours % 24, minutes)
            }
            return String(format: "%02d:%02d", totalHours, minutes)
        }

        if kind == .secondary {
            let days = totalHours / 24
            return String(format: "%dd %02d:%02d:%02d", days, totalHours % 24, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", totalHours, minutes, seconds)
    }
}
