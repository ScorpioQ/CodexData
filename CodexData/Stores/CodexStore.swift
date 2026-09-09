import Combine
import Foundation

@MainActor
final class CodexStore: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var windows: [QuotaWindow] = []

    private var client: CodexAppServerClient?
    private var pollingTask: Task<Void, Never>?

    init() {
        Task { await connect() }
    }

    func refresh() async {
        guard let client else {
            await connect()
            return
        }

        do {
            let limits = try await client.request("account/rateLimits/read")
            applyRateLimits(limits)
            connectionState = .live
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    private func connect() async {
        pollingTask?.cancel()
        client?.stop()
        connectionState = .connecting

        let client = CodexAppServerClient()
        client.onNotification = { [weak self] method, params in
            self?.handleNotification(method: method, params: params)
        }

        do {
            try client.start()
            self.client = client
            _ = try await client.request("initialize", params: [
                "clientInfo": [
                    "name": "codex_pulse",
                    "title": "Codex Pulse",
                    "version": "0.2.0"
                ]
            ])
            try client.notify("initialized")
            let limits = try await client.request("account/rateLimits/read")
            applyRateLimits(limits)
            connectionState = .live
            startPolling()
        } catch {
            self.client = nil
            windows = []
            connectionState = .failed(error.localizedDescription)
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    private func handleNotification(method: String, params: [String: Any]) {
        guard method == "account/rateLimits/updated" else { return }
        applyRateLimits(params)
        connectionState = .live
        startPolling()
    }

    private func applyRateLimits(_ response: [String: Any]) {
        let root = (response["result"] as? [String: Any]) ?? response
        let buckets: [String: Any]
        if let grouped = root["rateLimitsByLimitId"] as? [String: Any] {
            buckets = grouped
        } else if let single = root["rateLimits"] as? [String: Any] {
            buckets = ["codex": single]
        } else {
            return
        }

        var parsed: [QuotaWindow] = []
        for (limitID, rawBucket) in buckets {
            guard let bucket = rawBucket as? [String: Any] else { continue }
            for rawKind in ["primary", "secondary"] {
                guard let kind = QuotaWindow.Kind(rawValue: rawKind),
                      let data = bucket[rawKind] as? [String: Any] else { continue }
                let used = doubleNumber(data["usedPercent"])
                let reset = number(data["resetsAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
                guard used != nil || reset != nil else { continue }
                parsed.append(QuotaWindow(
                    id: "\(limitID)-\(rawKind)",
                    limitID: limitID,
                    kind: kind,
                    usedPercent: used,
                    resetDate: reset
                ))
            }
        }
        windows = parsed.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private func number(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func doubleNumber(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
