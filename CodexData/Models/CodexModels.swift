import Foundation

enum ConnectionState: Equatable {
    case idle
    case connecting
    case live
    case failed(String)

    nonisolated var label: String {
        AppText.connectionStateLabel(for: self)
    }
}

struct QuotaWindow: Identifiable, Equatable {
    enum Kind: String {
        case primary
        case secondary

        var title: String { self == .primary ? "5h" : "7d" }
    }

    let id: String
    let limitID: String
    let kind: Kind
    let usedPercent: Double?
    let resetDate: Date?

    var remainingPercent: Double? {
        guard let usedPercent else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }
}
