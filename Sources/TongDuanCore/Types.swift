import Foundation

public enum DetectScope: String, Codable, Sendable, Equatable, CaseIterable {
    case local
    case global

    public var title: String {
        switch self {
        case .local: return "局部检测"
        case .global: return "全局检测"
        }
    }
}

public enum HopVerdict: String, Codable, Sendable, Equatable {
    case tong = "通"
    case duan = "断"
    case partial = "部分"
    case unknown = "未知"
}

public enum PathModel: String, Codable, Sendable, Equatable, CaseIterable {
    case directClean = "直连干净"
    case systemProxy = "系统代理"
    case tunGlobal = "TUN/全局"
    case ruleSplit = "规则分流"
    case splitTunnel = "拆分隧道"
    case stale = "残留异常"
    case campusMixed = "校园混合"
    case unknown = "未知"
}

public enum Hop8Assessment: String, Codable, Sendable, Equatable {
    case notRun = "未探测"
    case localUpstreamDown = "本地链路或当前Wi-Fi上游没网"
    case foreignPathDown = "VPN或境外路径不通"
    case leftover = "本地残留或配置错误"
    case probesFailedOnly = "仅探测失败"
    case informationGap = "信息缺口"
    case reachable = "目标连通正常"
}

public enum Tone: String, Codable, Sendable, Equatable {
    case ok
    case bad
    case warn
    case muted
    case info
}

public struct HopResult: Codable, Sendable, Equatable, Identifiable {
    public var index: Int
    public var title: String
    public var verdict: HopVerdict
    public var summary: String
    public var evidence: [String]
    public var inferred: Bool
    public var informationGap: String?

    public var id: Int { index }

    public init(
        index: Int,
        title: String,
        verdict: HopVerdict,
        summary: String,
        evidence: [String],
        inferred: Bool = false,
        informationGap: String? = nil
    ) {
        self.index = index
        self.title = title
        self.verdict = verdict
        self.summary = summary
        self.evidence = evidence
        self.inferred = inferred
        self.informationGap = informationGap
    }
}

public struct DiagramNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var tone: Tone
    public var row: Int
    public var column: Int

    public init(id: String, title: String, detail: String, tone: Tone, row: Int, column: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.tone = tone
        self.row = row
        self.column = column
    }
}

public struct DiagramEdge: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var from: String
    public var to: String
    public var label: String
    public var inferred: Bool
    public var tone: Tone

    public init(id: String, from: String, to: String, label: String, inferred: Bool, tone: Tone) {
        self.id = id
        self.from = from
        self.to = to
        self.label = label
        self.inferred = inferred
        self.tone = tone
    }
}

public struct PathDiagram: Codable, Sendable, Equatable {
    public var model: PathModel
    public var nodes: [DiagramNode]
    public var edges: [DiagramEdge]
    public var footnotes: [String]

    public init(model: PathModel, nodes: [DiagramNode], edges: [DiagramEdge], footnotes: [String]) {
        self.model = model
        self.nodes = nodes
        self.edges = edges
        self.footnotes = footnotes
    }
}

public struct AppConflictNote: Codable, Sendable, Equatable {
    public var workBuddy: String
    public var claudeAndChatGPT: String
    /// Always false. The app never switches proxy or TUN mode by itself.
    public var willAutoSwitch: Bool
    public var refusal: String

    public init(workBuddy: String, claudeAndChatGPT: String, willAutoSwitch: Bool, refusal: String) {
        self.workBuddy = workBuddy
        self.claudeAndChatGPT = claudeAndChatGPT
        self.willAutoSwitch = willAutoSwitch
        self.refusal = refusal
    }
}

public struct NetworkObservation: Codable, Sendable, Equatable {
    public var linkKind: String
    public var linkUp: Bool
    public var ssid: String?
    public var ip: String?
    public var gateway: String?
    public var dns: [String]
    public var systemProxyOn: Bool
    public var systemProxyHost: String?
    public var systemProxyPort: Int?
    public var vpnClient: String?
    public var tunnelAddress: String?
    public var pathModel: PathModel

    public init(
        linkKind: String,
        linkUp: Bool,
        ssid: String?,
        ip: String?,
        gateway: String?,
        dns: [String],
        systemProxyOn: Bool,
        systemProxyHost: String?,
        systemProxyPort: Int?,
        vpnClient: String?,
        tunnelAddress: String?,
        pathModel: PathModel
    ) {
        self.linkKind = linkKind
        self.linkUp = linkUp
        self.ssid = ssid
        self.ip = ip
        self.gateway = gateway
        self.dns = dns
        self.systemProxyOn = systemProxyOn
        self.systemProxyHost = systemProxyHost
        self.systemProxyPort = systemProxyPort
        self.vpnClient = vpnClient
        self.tunnelAddress = tunnelAddress
        self.pathModel = pathModel
    }
}

public struct DiagnosisReport: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var scope: DetectScope
    public var hops: [HopResult]
    public var pathModel: PathModel
    public var pathFootnote: String
    public var diagram: PathDiagram
    public var conflict: AppConflictNote
    public var hop8: Hop8Assessment
    public var observation: NetworkObservation
    public var collectorNotes: [String]

    public init(
        generatedAt: Date,
        scope: DetectScope,
        hops: [HopResult],
        pathModel: PathModel,
        pathFootnote: String,
        diagram: PathDiagram,
        conflict: AppConflictNote,
        hop8: Hop8Assessment,
        observation: NetworkObservation,
        collectorNotes: [String]
    ) {
        self.generatedAt = generatedAt
        self.scope = scope
        self.hops = hops
        self.pathModel = pathModel
        self.pathFootnote = pathFootnote
        self.diagram = diagram
        self.conflict = conflict
        self.hop8 = hop8
        self.observation = observation
        self.collectorNotes = collectorNotes
    }
}

public enum HistoryTrigger: String, Codable, Sendable, Equatable {
    case detect = "检测"
    case stateChange = "状态变化"
    case periodic = "定时记录"
}

public struct HistoryEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var recordedAt: Date
    public var trigger: HistoryTrigger
    public var linkKind: String
    public var linkUp: Bool
    public var ssid: String?
    public var ip: String?
    public var gateway: String?
    public var dns: [String]
    public var systemProxyOn: Bool
    public var systemProxyPort: Int?
    public var vpnClient: String?
    public var tunnelAddress: String?
    public var pathModel: PathModel
    public var hopSummary: [String]
    public var diagram: PathDiagram
    public var hops: [HopResult]

    public init(
        id: String = UUID().uuidString,
        recordedAt: Date,
        trigger: HistoryTrigger,
        report: DiagnosisReport
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.trigger = trigger
        let o = report.observation
        self.linkKind = o.linkKind
        self.linkUp = o.linkUp
        self.ssid = o.ssid
        self.ip = o.ip
        self.gateway = o.gateway
        self.dns = o.dns
        self.systemProxyOn = o.systemProxyOn
        self.systemProxyPort = o.systemProxyPort
        self.vpnClient = o.vpnClient
        self.tunnelAddress = o.tunnelAddress
        self.pathModel = o.pathModel
        self.hopSummary = report.hops.map(\.verdict.rawValue)
        self.diagram = report.diagram
        self.hops = report.hops
    }
}

public enum RepairRisk: String, Codable, Sendable, Equatable {
    case safe
    case high
}

public enum RepairPhase: String, Codable, Sendable, Equatable {
    case repair
    case rollback
}

public enum RepairCommand: Codable, Sendable, Equatable {
    case setWebProxyState(service: String, enabled: Bool)
    case setSecureWebProxyState(service: String, enabled: Bool)
    case setSocksProxyState(service: String, enabled: Bool)
    case setAutoProxyState(service: String, enabled: Bool)
    case setProxyAutoDiscovery(service: String, enabled: Bool)
    case setDNSServers(service: String, servers: [String])
    case renewDHCP(interface: String)
    case stopSystemVPN(service: String)
    case startSystemVPN(service: String)
    case setWebProxy(service: String, host: String, port: Int)
    case setSecureWebProxy(service: String, host: String, port: Int)
    case setSocksProxy(service: String, host: String, port: Int)
    case clashSetMode(host: String, port: Int, mode: String)

    public var isClash: Bool {
        if case .clashSetMode = self { return true }
        return false
    }
}

public struct RepairItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var hop: Int
    public var title: String
    public var currentValue: String
    public var newValue: String
    public var risk: RepairRisk
    public var initiallyChecked: Bool
    public var commands: [RepairCommand]
    public var noticeOnly: Bool

    public var executable: Bool { !noticeOnly && !commands.isEmpty }

    public init(
        id: String,
        hop: Int,
        title: String,
        currentValue: String,
        newValue: String,
        risk: RepairRisk,
        commands: [RepairCommand],
        noticeOnly: Bool = false
    ) {
        self.id = id
        self.hop = hop
        self.title = title
        self.currentValue = currentValue
        self.newValue = newValue
        self.risk = risk
        self.initiallyChecked = risk == .safe && !noticeOnly && !commands.isEmpty
        self.commands = commands
        self.noticeOnly = noticeOnly
    }
}

public struct RepairPlan: Codable, Sendable, Equatable {
    public var items: [RepairItem]
    public var headline: String

    public init(items: [RepairItem], headline: String) {
        self.items = items
        self.headline = headline
    }

    public var executableItems: [RepairItem] { items.filter(\.executable) }
}

public struct ProxyEndpoint: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var server: String
    public var port: Int

    public init(enabled: Bool, server: String, port: Int) {
        self.enabled = enabled
        self.server = server
        self.port = port
    }
}

public struct ServiceSnapshot: Codable, Sendable, Equatable {
    public var name: String
    public var interfaceName: String?
    public var web: ProxyEndpoint?
    public var secure: ProxyEndpoint?
    public var socks: ProxyEndpoint?
    public var pacEnabled: Bool
    public var pacURL: String?
    public var wpad: Bool
    public var dnsServers: [String]
    public var dnsWasEmpty: Bool

    public init(
        name: String,
        interfaceName: String?,
        web: ProxyEndpoint?,
        secure: ProxyEndpoint?,
        socks: ProxyEndpoint?,
        pacEnabled: Bool,
        pacURL: String?,
        wpad: Bool,
        dnsServers: [String],
        dnsWasEmpty: Bool
    ) {
        self.name = name
        self.interfaceName = interfaceName
        self.web = web
        self.secure = secure
        self.socks = socks
        self.pacEnabled = pacEnabled
        self.pacURL = pacURL
        self.wpad = wpad
        self.dnsServers = dnsServers
        self.dnsWasEmpty = dnsWasEmpty
    }
}

public struct RepairSnapshot: Codable, Sendable, Equatable {
    public var id: String
    public var takenAt: Date
    public var services: [ServiceSnapshot]
    public var vpnConnected: [String]
    public var clashMode: String?
    public var clashAPIHost: String?
    public var clashAPIPort: Int?

    public init(
        id: String = UUID().uuidString,
        takenAt: Date,
        services: [ServiceSnapshot],
        vpnConnected: [String],
        clashMode: String?,
        clashAPIHost: String?,
        clashAPIPort: Int?
    ) {
        self.id = id
        self.takenAt = takenAt
        self.services = services
        self.vpnConnected = vpnConnected
        self.clashMode = clashMode
        self.clashAPIHost = clashAPIHost
        self.clashAPIPort = clashAPIPort
    }
}

public enum RepairError: Error, Equatable, CustomStringConvertible {
    case forbidden(String)
    case failed(String)

    public var description: String {
        switch self {
        case .forbidden(let reason): return "已拒绝：\(reason)"
        case .failed(let reason): return reason
        }
    }
}

public enum RepairConfirmation {
    public static func quickCleanEnabled(hasDiagnosis: Bool) -> Bool {
        hasDiagnosis
    }

    public static func initialChecked(_ items: [RepairItem]) -> Set<String> {
        Set(items.filter(\.initiallyChecked).map(\.id))
    }

    /// Confirm starts unchecked. High-risk items also need the second checkbox.
    public static func canApply(
        items: [RepairItem],
        checked: Set<String>,
        confirmed: Bool,
        highRiskConfirmed: Bool
    ) -> Bool {
        guard confirmed else { return false }
        let chosen = items.filter { checked.contains($0.id) && $0.executable }
        guard !chosen.isEmpty else { return false }
        if chosen.contains(where: { $0.risk == .high }) && !highRiskConfirmed {
            return false
        }
        return true
    }
}
