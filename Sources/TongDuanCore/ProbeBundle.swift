import Foundation

/// Raw command output plus the few probe results a collector already measured.
/// The classifier never shells out. Tests and the dry-run CLI feed this struct.
public struct ProbeBundle: Equatable, Sendable {
    public var hardwarePorts: String = ""
    public var networkServices: String = ""
    public var serviceInfo: [String: String] = [:]
    public var webProxy: [String: String] = [:]
    public var secureWebProxy: [String: String] = [:]
    public var socksProxy: [String: String] = [:]
    public var autoProxyURL: [String: String] = [:]
    public var autoDiscovery: [String: String] = [:]
    public var dnsServers: [String: String] = [:]
    public var scutilProxy: String = ""
    public var scutilDNS: String = ""
    public var scutilNC: String = ""
    public var routeGetDefault: String = ""
    public var netstatRN: String = ""
    public var ifconfig: String = ""
    public var lsof: String = ""
    public var processList: String = ""
    public var wifiInfo: String = ""
    public var clashAPI: String?
    public var clashAPIBase: String?
    public var scope: DetectScope = .local
    public var gatewayProbeOK: Bool?
    public var gatewayProbeDetail: String = ""
    public var domesticDirectOK: Bool?
    public var domesticDirectDetail: String = ""
    public var foreignDirectOK: Bool?
    public var foreignDirectDetail: String = ""
    public var foreignViaTunnelOK: Bool?
    public var foreignViaTunnelDetail: String = ""
    public var foreignViaTunnelAttempted: Bool = false
    public var icmp1111OK: Bool?
    public var icmp1111Detail: String = ""
    public var notes: [String] = []

    public init() {}
}

extension ProbeBundle: Codable {
    enum CodingKeys: String, CodingKey {
        case hardwarePorts, networkServices, serviceInfo, webProxy, secureWebProxy, socksProxy
        case autoProxyURL, autoDiscovery, dnsServers, scutilProxy, scutilDNS, scutilNC
        case routeGetDefault, netstatRN, ifconfig, lsof, processList, wifiInfo
        case clashAPI, clashAPIBase, scope, gatewayProbeOK, gatewayProbeDetail
        case domesticDirectOK, domesticDirectDetail, foreignDirectOK, foreignDirectDetail
        case foreignViaTunnelOK, foreignViaTunnelDetail, foreignViaTunnelAttempted
        case icmp1111OK, icmp1111Detail, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        hardwarePorts = try c.decodeIfPresent(String.self, forKey: .hardwarePorts) ?? ""
        networkServices = try c.decodeIfPresent(String.self, forKey: .networkServices) ?? ""
        serviceInfo = try c.decodeIfPresent([String: String].self, forKey: .serviceInfo) ?? [:]
        webProxy = try c.decodeIfPresent([String: String].self, forKey: .webProxy) ?? [:]
        secureWebProxy = try c.decodeIfPresent([String: String].self, forKey: .secureWebProxy) ?? [:]
        socksProxy = try c.decodeIfPresent([String: String].self, forKey: .socksProxy) ?? [:]
        autoProxyURL = try c.decodeIfPresent([String: String].self, forKey: .autoProxyURL) ?? [:]
        autoDiscovery = try c.decodeIfPresent([String: String].self, forKey: .autoDiscovery) ?? [:]
        dnsServers = try c.decodeIfPresent([String: String].self, forKey: .dnsServers) ?? [:]
        scutilProxy = try c.decodeIfPresent(String.self, forKey: .scutilProxy) ?? ""
        scutilDNS = try c.decodeIfPresent(String.self, forKey: .scutilDNS) ?? ""
        scutilNC = try c.decodeIfPresent(String.self, forKey: .scutilNC) ?? ""
        routeGetDefault = try c.decodeIfPresent(String.self, forKey: .routeGetDefault) ?? ""
        netstatRN = try c.decodeIfPresent(String.self, forKey: .netstatRN) ?? ""
        ifconfig = try c.decodeIfPresent(String.self, forKey: .ifconfig) ?? ""
        lsof = try c.decodeIfPresent(String.self, forKey: .lsof) ?? ""
        processList = try c.decodeIfPresent(String.self, forKey: .processList) ?? ""
        wifiInfo = try c.decodeIfPresent(String.self, forKey: .wifiInfo) ?? ""
        clashAPI = try c.decodeIfPresent(String.self, forKey: .clashAPI)
        clashAPIBase = try c.decodeIfPresent(String.self, forKey: .clashAPIBase)
        scope = try c.decodeIfPresent(DetectScope.self, forKey: .scope) ?? .local
        gatewayProbeOK = try c.decodeIfPresent(Bool.self, forKey: .gatewayProbeOK)
        gatewayProbeDetail = try c.decodeIfPresent(String.self, forKey: .gatewayProbeDetail) ?? ""
        domesticDirectOK = try c.decodeIfPresent(Bool.self, forKey: .domesticDirectOK)
        domesticDirectDetail = try c.decodeIfPresent(String.self, forKey: .domesticDirectDetail) ?? ""
        foreignDirectOK = try c.decodeIfPresent(Bool.self, forKey: .foreignDirectOK)
        foreignDirectDetail = try c.decodeIfPresent(String.self, forKey: .foreignDirectDetail) ?? ""
        foreignViaTunnelOK = try c.decodeIfPresent(Bool.self, forKey: .foreignViaTunnelOK)
        foreignViaTunnelDetail = try c.decodeIfPresent(String.self, forKey: .foreignViaTunnelDetail) ?? ""
        foreignViaTunnelAttempted = try c.decodeIfPresent(Bool.self, forKey: .foreignViaTunnelAttempted) ?? false
        icmp1111OK = try c.decodeIfPresent(Bool.self, forKey: .icmp1111OK)
        icmp1111Detail = try c.decodeIfPresent(String.self, forKey: .icmp1111Detail) ?? ""
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}
