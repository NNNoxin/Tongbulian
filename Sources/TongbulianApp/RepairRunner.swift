import Foundation

private final class ClashReply: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var status = 0
    var body = ""
}

enum RepairRunner {
    static func apply(_ commands: [RepairCommand], phase: RepairPhase, snapshot: RepairSnapshot?) throws -> String {
        guard !commands.isEmpty else { throw RepairError.failed("没有可执行的修复项") }
        for command in commands {
            try RepairGuard.validate(command, phase: phase, snapshot: snapshot)
        }
        let shell = commands.filter { !$0.isClash }
        for command in shell {
            let argv = RepairGuard.argv(for: command)
            guard RepairGuard.allowsArgv(argv, phase: phase, snapshot: snapshot) else {
                throw RepairError.forbidden(argv.joined(separator: " "))
            }
        }
        var lines: [String] = []
        if !shell.isEmpty {
            let transcript = try runAdmin(shell.map { RepairGuard.argv(for: $0) })
            lines.append(transcript)
        }
        for command in commands {
            guard case .clashSetMode(let host, let port, let mode) = command else { continue }
            try patchClash(host: host, port: port, mode: mode)
            lines.append("已请求 http://127.0.0.1:\(port)/configs 把 mode 设为 \(mode)")
        }
        return lines.joined(separator: "\n")
    }

    private static func runAdmin(_ argvs: [[String]]) throws -> String {
        let joined = argvs.map { argv in
            argv.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        }.joined(separator: " && ")
        let escaped = joined
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        let result = runProcess(["/usr/bin/osascript", "-e", source], timeout: 180)
        if result.code != 0 {
            let detail = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RepairError.failed(detail.isEmpty ? "系统没有接受这次修改" : detail)
        }
        return joined
    }

    private static func patchClash(host: String, port: Int, mode: String) throws {
        guard host == "127.0.0.1" || host == "localhost" else {
            throw RepairError.forbidden("Clash API 不在本机")
        }
        guard ["rule", "global", "direct"].contains(mode) else {
            throw RepairError.forbidden("不允许的 Clash 模式")
        }
        guard let url = URL(string: "http://127.0.0.1:\(port)/configs") else {
            throw RepairError.forbidden("Clash 地址无效")
        }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"mode\":\"\(mode)\"}".utf8)
        let box = ClashReply()
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            box.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            box.body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            box.semaphore.signal()
        }
        task.resume()
        _ = box.semaphore.wait(timeout: .now() + 5)
        task.cancel()
        guard (200..<300).contains(box.status) else {
            throw RepairError.failed("Clash API 返回 \(box.status)。通不连不会猜测密钥。\(box.body)")
        }
    }

    private static func runProcess(_ argv: [String], timeout: TimeInterval) -> (code: Int32, text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return (127, "") }
        let group = DispatchGroup()
        var stdout = Data()
        var stderr = Data()
        group.enter()
        DispatchQueue.global().async {
            stdout = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderr = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
        group.wait()
        let text = String(data: stdout + stderr, encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }
}
