import Foundation

@MainActor
final class CodexAppServerClient {
    enum ClientError: LocalizedError {
        case codexNotFound
        case invalidResponse
        case processStopped
        case remote(String)

        var errorDescription: String? {
            switch self {
            case .codexNotFound: AppText.codexNotFound
            case .invalidResponse: AppText.invalidResponse
            case .processStopped: AppText.processStopped
            case .remote(let message): message
            }
        }
    }

    var onNotification: ((String, [String: Any]) -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var continuations: [Int: CheckedContinuation<[String: Any], Error>] = [:]

    func start() throws {
        guard process == nil else { return }
        guard let executable = Self.findCodexExecutable() else { throw ClientError.codexNotFound }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleTermination() }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self] in self?.handleTermination() }
                return
            }
            Task { @MainActor [weak self] in self?.consume(data) }
        }

        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
    }

    func stop() {
        output?.readabilityHandler = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        input = nil
        output = nil
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume(throwing: ClientError.processStopped) }
    }

    func request(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard process != nil else { throw ClientError.processStopped }

        let id = nextID
        nextID += 1
        var message: [String: Any] = ["method": method, "id": id]
        if !params.isEmpty { message["params"] = params }
        let data = try Self.lineData(for: message)

        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
            input?.write(data)
        }
    }

    func notify(_ method: String, params: [String: Any] = [:]) throws {
        var message: [String: Any] = ["method": method]
        if !params.isEmpty { message["params"] = params }
        input?.write(try Self.lineData(for: message))
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty, let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        if let id = (message["id"] as? NSNumber)?.intValue {
            guard let continuation = continuations.removeValue(forKey: id) else { return }
            if let error = message["error"] as? [String: Any] {
                continuation.resume(throwing: ClientError.remote(error["message"] as? String ?? AppText.requestFailed))
            } else if let result = message["result"] as? [String: Any] {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: ClientError.invalidResponse)
            }
            return
        }

        guard let method = message["method"] as? String else { return }
        onNotification?(method, message["params"] as? [String: Any] ?? [:])
    }

    private func handleTermination() {
        guard process != nil else { return }
        process = nil
        input = nil
        output = nil
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume(throwing: ClientError.processStopped) }
    }

    private static func lineData(for object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw ClientError.invalidResponse }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }

    private static func findCodexExecutable() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return path }

        let which = Process()
        let pipe = Pipe()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["codex"]
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }
}
