import Foundation

public enum ShanghaiClock {
    public static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!

    public static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date) + " Asia/Shanghai"
    }
}

public func historyEvent(from report: DiagnosisReport, trigger: HistoryTrigger, at date: Date = Date(), id: String = UUID().uuidString) -> HistoryEvent {
    var event = HistoryEvent(id: id, recordedAt: date, trigger: trigger, report: report)
    event.recordedAt = date
    return event
}

public func networkSignature(_ report: DiagnosisReport, includeHop8: Bool = false) -> String {
    let observation = report.observation
    let limit = includeHop8 ? 8 : 7
    let hops = report.hops.prefix(limit).map(\.verdict.rawValue).joined(separator: ",")
    let dns = observation.dns.joined(separator: ",")
    return [
        observation.linkKind,
        observation.linkUp ? "up" : "down",
        observation.ssid ?? "",
        observation.ip ?? "",
        observation.gateway ?? "",
        dns,
        observation.systemProxyOn ? "proxy" : "direct",
        observation.systemProxyPort.map(String.init) ?? "",
        observation.vpnClient ?? "",
        observation.tunnelAddress ?? "",
        observation.pathModel.rawValue,
        hops,
    ].joined(separator: "|")
}

public final class HistoryStore: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    public static let retention: TimeInterval = 24 * 60 * 60

    public init(directory: URL) {
        self.file = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func load(now: Date = Date()) -> [HistoryEvent] {
        lock.lock()
        defer { lock.unlock() }
        let kept = prune(readUnlocked(), now: now)
        writeUnlocked(kept)
        return kept.sorted { $0.recordedAt > $1.recordedAt }
    }

    public func append(_ event: HistoryEvent, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var items = readUnlocked()
        items.append(event)
        writeUnlocked(prune(items, now: now))
    }

    public func replaceAll(_ events: [HistoryEvent], now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        writeUnlocked(prune(events, now: now))
    }

    private func prune(_ events: [HistoryEvent], now: Date) -> [HistoryEvent] {
        events.filter { now.timeIntervalSince($0.recordedAt) <= Self.retention }
    }

    private func readUnlocked() -> [HistoryEvent] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([HistoryEvent].self, from: data)) ?? []
    }

    private func writeUnlocked(_ events: [HistoryEvent]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
