import Foundation

enum ServiceKind: Equatable {
    case wifi
    case ethernet
    case other
}

struct ProxySetting: Equatable {
    var enabled: Bool
    var server: String
    var port: Int
}

struct ServiceFact: Equatable {
    var name: String
    var disabled: Bool
    var kind: ServiceKind
    var device: String?
    var method: String
    var ip: String?
    var router: String?
    var infoMissing: Bool
    var web: ProxySetting?
    var secure: ProxySetting?
    var socks: ProxySetting?
    var proxyMissing: Bool
    var pacEnabled: Bool
    var pacURL: String?
    var wpad: Bool
    var dns: [String]
    var dnsExplicitEmpty: Bool
    var dnsMissing: Bool
}

struct WiFiFact: Equatable {
    var hardwarePresent: Bool
    var stateKnown: Bool
    var powerOff: Bool
    var associated: Bool
    var ssid: String?
    var rssi: Int?
    var interfaceName: String?
}

struct DefaultRoute: Equatable {
    var gateway: String
    var interfaceName: String
}

struct PortListener: Equatable {
    var process: String
    var address: String
    var port: Int
    var proto: String
}

enum ClientBrand: String, Equatable {
    case clashVerge = "Clash Verge"
    case clash = "Clash"
    case surge = "Surge"
    case wireguard = "WireGuard"
    case singBox = "sing-box"
    case v2ray = "V2Ray"
    case tailscale = "Tailscale"
    case anyconnect = "AnyConnect"
    case atrust = "aTrust"
    case openvpn = "OpenVPN"
}

struct DetectedClient: Equatable {
    var brand: ClientBrand
}

struct VPNFact: Equatable {
    var name: String
    var connected: Bool
    var kind: String
}

struct ClashFact: Equatable {
    var host: String
    var port: Int
    var mode: String?
    var tun: Bool?
    var mixedPort: Int?
}

struct IfaceFact: Equatable {
    var name: String
    var inet: String?
}

struct ScutilProxy: Equatable {
    var httpOn: Bool = false
    var httpHost: String = ""
    var httpPort: Int = 0
    var httpsOn: Bool = false
    var httpsHost: String = ""
    var httpsPort: Int = 0
    var socksOn: Bool = false
    var socksHost: String = ""
    var socksPort: Int = 0
    var pacOn: Bool = false
    var wpadOn: Bool = false
}

struct LocalSignals: Equatable {
    var services: [ServiceFact]
    var wifi: WiFiFact
    var dnsFromScutil: [String]
    var scutilProxy: ScutilProxy
    var routes: [DefaultRoute]
    var sawRouteOutput: Bool
    var routeFailed: Bool
    var listeners: [PortListener]
    var clients: [DetectedClient]
    var vpn: [VPNFact]
    var clash: ClashFact?
    var ifaces: [IfaceFact]
    var hasEvidence: Bool
    var scope: DetectScope
    var gatewayProbeOK: Bool?
    var gatewayProbeDetail: String
    var domesticDirectOK: Bool?
    var domesticDirectDetail: String
    var foreignDirectOK: Bool?
    var foreignDirectDetail: String
    var foreignViaTunnelOK: Bool?
    var foreignViaTunnelDetail: String
    var foreignViaTunnelAttempted: Bool
    var icmp1111OK: Bool?
    var icmp1111Detail: String
    var notes: [String]
}

enum Parser {
    static func parse(_ bundle: ProbeBundle) -> LocalSignals {
        let hardware = parseHardware(bundle.hardwarePorts)
        let serviceRows = parseServiceList(bundle.networkServices)
        let services = serviceRows.map { row in
            makeService(row.name, disabled: row.disabled, hardware: hardware, bundle: bundle)
        }
        let ifaces = parseIfconfig(bundle.ifconfig)
        let routes = parseRoutes(netstat: bundle.netstatRN, routeGet: bundle.routeGetDefault)
        let routeFailed = bundle.routeGetDefault.localizedCaseInsensitiveContains("not in table")
            || bundle.routeGetDefault.localizedCaseInsensitiveContains("bad address")
        let sawRoute = !bundle.netstatRN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bundle.routeGetDefault.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasEvidence = !bundle.hardwarePorts.isEmpty
            || !bundle.networkServices.isEmpty
            || !bundle.ifconfig.isEmpty
            || sawRoute
            || !bundle.wifiInfo.isEmpty

        return LocalSignals(
            services: services,
            wifi: parseWiFi(bundle.wifiInfo, hardware: hardware),
            dnsFromScutil: parseScutilDNS(bundle.scutilDNS),
            scutilProxy: parseScutilProxy(bundle.scutilProxy),
            routes: routes,
            sawRouteOutput: sawRoute,
            routeFailed: routeFailed,
            listeners: parseListeners(bundle.lsof),
            clients: parseClients(bundle.processList),
            vpn: parseVPN(bundle.scutilNC),
            clash: parseClash(json: bundle.clashAPI, base: bundle.clashAPIBase),
            ifaces: ifaces,
            hasEvidence: hasEvidence,
            scope: bundle.scope,
            gatewayProbeOK: bundle.gatewayProbeOK,
            gatewayProbeDetail: bundle.gatewayProbeDetail,
            domesticDirectOK: bundle.domesticDirectOK,
            domesticDirectDetail: bundle.domesticDirectDetail,
            foreignDirectOK: bundle.foreignDirectOK,
            foreignDirectDetail: bundle.foreignDirectDetail,
            foreignViaTunnelOK: bundle.foreignViaTunnelOK,
            foreignViaTunnelDetail: bundle.foreignViaTunnelDetail,
            foreignViaTunnelAttempted: bundle.foreignViaTunnelAttempted,
            icmp1111OK: bundle.icmp1111OK,
            icmp1111Detail: bundle.icmp1111Detail,
            notes: bundle.notes
        )
    }

    static func parseHardware(_ text: String) -> [(port: String, device: String)] {
        var port = ""
        var rows: [(String, String)] = []
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") {
                port = String(line.dropFirst("Hardware Port:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:"), !port.isEmpty {
                let device = String(line.dropFirst("Device:".count)).trimmingCharacters(in: .whitespaces)
                rows.append((port, device))
                port = ""
            }
        }
        return rows
    }

    static func parseServiceList(_ text: String) -> [(name: String, disabled: Bool)] {
        var rows: [(String, Bool)] = []
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.localizedCaseInsensitiveContains("denotes that a network service is disabled") { continue }
            if line.hasPrefix("*") {
                let name = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { rows.append((name, true)) }
            } else {
                rows.append((line, false))
            }
        }
        return rows
    }

    static func makeService(
        _ name: String,
        disabled: Bool,
        hardware: [(port: String, device: String)],
        bundle: ProbeBundle
    ) -> ServiceFact {
        let kind = kindOf(name, hardware: hardware)
        let device = hardware.first { $0.port.caseInsensitiveCompare(name) == .orderedSame }?.device
            ?? hardware.first { name.localizedCaseInsensitiveContains($0.port) || $0.port.localizedCaseInsensitiveContains(name) }?.device
        let infoText = bundle.serviceInfo[name] ?? ""
        let info = parseInfo(infoText)
        let webText = bundle.webProxy[name] ?? ""
        let httpsText = bundle.secureWebProxy[name] ?? ""
        let socksText = bundle.socksProxy[name] ?? ""
        let pacText = bundle.autoProxyURL[name] ?? ""
        let wpadText = bundle.autoDiscovery[name] ?? ""
        let dnsText = bundle.dnsServers[name] ?? ""
        let dns = parseDNSList(dnsText)
        let pac = parsePAC(pacText)
        return ServiceFact(
            name: name,
            disabled: disabled,
            kind: kind,
            device: device,
            method: info.method,
            ip: info.ip,
            router: info.router,
            infoMissing: infoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            web: parseProxyBlock(webText),
            secure: parseProxyBlock(httpsText),
            socks: parseProxyBlock(socksText),
            proxyMissing: webText.isEmpty && httpsText.isEmpty && socksText.isEmpty,
            pacEnabled: pac.enabled,
            pacURL: pac.url,
            wpad: parseWPAD(wpadText),
            dns: dns.servers,
            dnsExplicitEmpty: dns.explicitEmpty,
            dnsMissing: dnsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    static func kindOf(_ name: String, hardware: [(port: String, device: String)]) -> ServiceKind {
        let blob = (name + " " + (hardware.first { $0.port == name }?.port ?? "")).lowercased()
        if blob.contains("wi-fi") || blob.contains("wifi") || blob.contains("airport") { return .wifi }
        if blob.contains("ethernet") || blob.contains("lan") || blob.contains("usb") || blob.contains("thunderbolt") {
            return .ethernet
        }
        return .other
    }

    static func parseInfo(_ text: String) -> (method: String, ip: String?, router: String?) {
        var method = "unknown"
        if text.contains("DHCP Configuration") { method = "DHCP" }
        else if text.contains("Manual Configuration") { method = "Manual" }
        else if text.localizedCaseInsensitiveContains("BootP") { method = "BootP" }
        var ip: String?
        var router: String?
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let value = field(line, "IP address:") { ip = cleanIP(value) }
            if let value = field(line, "Router:") { router = cleanIP(value) }
        }
        return (method, ip, router)
    }

    static func parseProxyBlock(_ text: String) -> ProxySetting? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        var enabled = false
        var server = ""
        var port = 0
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Enabled:"), !line.hasPrefix("Authenticated") {
                let value = (field(line, "Enabled:") ?? "").lowercased()
                enabled = value == "yes" || value == "1" || value == "on"
            } else if line.hasPrefix("Server:") {
                server = field(line, "Server:") ?? ""
            } else if line.hasPrefix("Port:") {
                port = Int(field(line, "Port:") ?? "") ?? 0
            }
        }
        return ProxySetting(enabled: enabled, server: server.trimmingCharacters(in: .whitespaces), port: port)
    }

    static func parsePAC(_ text: String) -> (enabled: Bool, url: String?) {
        var enabled = false
        var url: String?
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Enabled:") {
                let value = (field(line, "Enabled:") ?? "").lowercased()
                enabled = value == "yes" || value == "1" || value == "on"
            } else if line.hasPrefix("URL:") {
                let value = field(line, "URL:") ?? ""
                if value.isEmpty || value == "(null)" || value.lowercased() == "none" {
                    url = nil
                } else {
                    url = value
                }
            }
        }
        return (enabled, url)
    }

    static func parseWPAD(_ text: String) -> Bool {
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.localizedCaseInsensitiveContains("auto proxy discovery") {
                let lower = line.lowercased()
                return lower.contains(": on") || lower.hasSuffix(" on") || lower.contains(": yes")
            }
        }
        return false
    }

    static func parseDNSList(_ text: String) -> (servers: [String], explicitEmpty: Bool) {
        if text.localizedCaseInsensitiveContains("aren't any dns") {
            return ([], true)
        }
        var servers: [String] = []
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if looksLikeHost(line) { servers.append(line) }
        }
        return (servers, false)
    }

    static func parseScutilDNS(_ text: String) -> [String] {
        var servers: [String] = []
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "nameserver[", options: .caseInsensitive) else { continue }
            let tail = line[range.lowerBound...]
            guard let colon = tail.firstIndex(of: ":") else { continue }
            let value = tail[tail.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if looksLikeHost(value) { servers.append(value) }
        }
        return unique(servers)
    }

    static func parseScutilProxy(_ text: String) -> ScutilProxy {
        var map: [String: String] = [:]
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { map[key] = value }
        }
        func on(_ key: String) -> Bool { map[key] == "1" }
        func port(_ key: String) -> Int { Int(map[key] ?? "") ?? 0 }
        var proxy = ScutilProxy()
        proxy.httpOn = on("HTTPEnable")
        proxy.httpHost = map["HTTPProxy"] ?? ""
        proxy.httpPort = port("HTTPPort")
        proxy.httpsOn = on("HTTPSEnable")
        proxy.httpsHost = map["HTTPSProxy"] ?? ""
        proxy.httpsPort = port("HTTPSPort")
        proxy.socksOn = on("SOCKSEnable")
        proxy.socksHost = map["SOCKSProxy"] ?? ""
        proxy.socksPort = port("SOCKSPort")
        proxy.pacOn = on("ProxyAutoConfigEnable")
        proxy.wpadOn = on("ProxyAutoDiscoveryEnable")
        return proxy
    }

    static func parseRoutes(netstat: String, routeGet: String) -> [DefaultRoute] {
        var routes: [DefaultRoute] = []
        for raw in lines(netstat) {
            let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 4, parts[0] == "default" else { continue }
            routes.append(DefaultRoute(gateway: parts[1], interfaceName: parts[3]))
        }
        if !routes.isEmpty { return routes }
        var gateway = ""
        var iface = ""
        for raw in lines(routeGet) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let value = field(line, "gateway:") { gateway = value }
            if let value = field(line, "interface:") { iface = value }
        }
        if !gateway.isEmpty, !iface.isEmpty, !routeGet.localizedCaseInsensitiveContains("not in table") {
            return [DefaultRoute(gateway: gateway, interfaceName: iface)]
        }
        return []
    }

    static func parseIfconfig(_ text: String) -> [IfaceFact] {
        var facts: [IfaceFact] = []
        var current: String?
        var inet: String?
        func flush() {
            if let name = current {
                facts.append(IfaceFact(name: name, inet: inet))
            }
            current = nil
            inet = nil
        }
        for raw in lines(text) {
            if !raw.hasPrefix("\t"), !raw.hasPrefix(" "), raw.contains("flags=") {
                flush()
                let name = raw.split(separator: ":").first.map(String.init) ?? ""
                current = name
            } else if raw.trimmingCharacters(in: .whitespaces).hasPrefix("inet ") {
                let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                if parts.count >= 2 { inet = parts[1] }
            }
        }
        flush()
        return facts
    }

    static func parseListeners(_ text: String) -> [PortListener] {
        var listeners: [PortListener] = []
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let proto: String
            if line.contains("(LISTEN)") { proto = "tcp" }
            else if line.contains(" UDP ") || line.contains("\tUDP ") { proto = "udp" }
            else { continue }
            guard let parsed = endpoint(in: line, proto: proto) else { continue }
            let process = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            listeners.append(PortListener(process: process, address: parsed.address, port: parsed.port, proto: proto))
        }
        return listeners
    }

    static func endpoint(in line: String, proto: String) -> (address: String, port: Int)? {
        let marker = proto == "tcp" ? "TCP " : "UDP "
        guard let range = line.range(of: marker) else { return nil }
        var tail = line[range.upperBound...]
        if let space = tail.firstIndex(of: " ") {
            tail = tail[..<space]
        }
        if tail.hasSuffix("(LISTEN)") {
            tail = tail.dropLast("(LISTEN)".count)
        }
        let token = tail.trimmingCharacters(in: .whitespaces)
        guard let colon = token.lastIndex(of: ":") else { return nil }
        let host = String(token[..<colon])
        let portString = String(token[token.index(after: colon)...])
        guard let port = Int(portString) else { return nil }
        return (host, port)
    }

    static func parseClients(_ text: String) -> [DetectedClient] {
        let lower = text.lowercased()
        func has(_ needle: String) -> Bool { lower.contains(needle) }
        var brands: [ClientBrand] = []
        let verge = has("verge-mihomo") || has("clash verge") || has("clash-verge")
        if verge { brands.append(.clashVerge) }
        if !verge && (has("clash-meta") || has("mihomo") || has("/clash") || has(" clash")) {
            brands.append(.clash)
        }
        if has("surge") { brands.append(.surge) }
        if has("wireguard") || has("wg-quick") { brands.append(.wireguard) }
        if has("sing-box") { brands.append(.singBox) }
        if has("v2ray") || has("xray") { brands.append(.v2ray) }
        if has("tailscaled") || has("tailscale") { brands.append(.tailscale) }
        if has("anyconnect") || has("vpnagentd") { brands.append(.anyconnect) }
        if has("atrust") { brands.append(.atrust) }
        if has("openvpn") || has("tunnelblick") { brands.append(.openvpn) }
        return brands.map { DetectedClient(brand: $0) }
    }

    static func parseVPN(_ text: String) -> [VPNFact] {
        var facts: [VPNFact] = []
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let connected = line.contains("(Connected)")
            let disconnected = line.contains("(Disconnected)")
            guard connected || disconnected else { continue }
            guard let open = line.firstIndex(of: "\""), let close = line[line.index(after: open)...].firstIndex(of: "\"") else {
                continue
            }
            let name = String(line[line.index(after: open)..<close])
            var kind = ""
            if let bracket = line.lastIndex(of: "[") {
                kind = String(line[line.index(after: bracket)...]).trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            }
            facts.append(VPNFact(name: name, connected: connected, kind: kind))
        }
        return facts
    }

    static func parseClash(json: String?, base: String?) -> ClashFact? {
        guard let base, let url = URL(string: base), let host = url.host, isLoopback(host) else { return nil }
        guard let json, let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let port = url.port ?? 9090
        var tun: Bool?
        if let tunObj = obj["tun"] as? [String: Any] {
            tun = tunObj["enable"] as? Bool
        }
        let mixed = obj["mixed-port"] as? Int ?? obj["port"] as? Int
        let mode = (obj["mode"] as? String)?.lowercased()
        return ClashFact(host: host, port: port, mode: mode, tun: tun, mixedPort: mixed)
    }

    static func parseWiFi(_ text: String, hardware: [(port: String, device: String)]) -> WiFiFact {
        let hardwarePresent = hardware.contains {
            let port = $0.port.lowercased()
            return port.contains("wi-fi") || port.contains("wifi") || port.contains("airport")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        var fact = WiFiFact(
            hardwarePresent: hardwarePresent,
            stateKnown: !trimmed.isEmpty || !hardwarePresent,
            powerOff: false,
            associated: false,
            ssid: nil,
            rssi: nil,
            interfaceName: hardware.first { $0.port.lowercased().contains("wi-fi") || $0.port.lowercased().contains("wifi") }?.device
        )
        if lower.contains("power: off") || lower.contains("wi-fi is off") || lower.contains("airport: off") || lower.contains("wi-fi power is off") {
            fact.powerOff = true
        }
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let value = field(line, "interface:") ?? field(line, "Interface:") {
                fact.interfaceName = value
            }
            if line.lowercased().hasPrefix("rssi:") {
                let number = line.dropFirst("RSSI:".count).trimmingCharacters(in: .whitespaces)
                fact.rssi = Int(number)
            }
            if let value = field(line, "Current Wi-Fi Network:") {
                let cleaned = value.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && !cleaned.localizedCaseInsensitiveContains("not associated") {
                    fact.ssid = cleaned
                    fact.associated = !fact.powerOff
                }
            }
        }
        if lower.contains("you are not associated") || lower.contains("not associated with") {
            fact.associated = false
            if fact.ssid == nil { fact.ssid = nil }
        }
        return fact
    }
}

public func networkServiceNames(_ text: String) -> [String] {
    Parser.parseServiceList(text).map(\.name)
}

public func hardwareDevices(_ text: String) -> [(port: String, device: String)] {
    Parser.parseHardware(text)
}

func lines(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
}

func field(_ line: String, _ prefix: String) -> String? {
    guard line.hasPrefix(prefix) || line.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
    let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    return value
}

func cleanIP(_ value: String) -> String? {
    let token = value.trimmingCharacters(in: .whitespaces)
    if token.isEmpty || token == "none" || token == "(null)" || token == "-" { return nil }
    return token
}

func looksLikeHost(_ value: String) -> Bool {
    if value.isEmpty || value.contains(" ") { return false }
    if value.contains(":") { return true }
    let parts = value.split(separator: ".")
    if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) { return true }
    return false
}

func isLoopback(_ host: String) -> Bool {
    let h = host.trimmingCharacters(in: .whitespaces).lowercased()
    return h == "127.0.0.1" || h == "localhost" || h == "::1" || h == "[::1]"
}

func isLinkLocal(_ ip: String?) -> Bool {
    guard let ip else { return false }
    return ip.hasPrefix("169.254.")
}

func usableIPv4(_ ip: String?) -> Bool {
    guard let ip, !ip.isEmpty, ip != "0.0.0.0" else { return false }
    return !isLinkLocal(ip)
}

func unique(_ values: [String]) -> [String] {
    var seen: [String] = []
    for value in values where !seen.contains(value) {
        seen.append(value)
    }
    return seen
}

func isListening(_ host: String, _ port: Int, _ listeners: [PortListener]) -> Bool {
    listeners.contains { listener in
        listener.port == port && hostsMatch(listener.address, host)
    }
}

func hostsMatch(_ listener: String, _ wanted: String) -> Bool {
    if listener == "*" || listener == "0.0.0.0" || listener == "*" { return true }
    if listener.caseInsensitiveCompare(wanted) == .orderedSame { return true }
    if isLoopback(wanted) && (isLoopback(listener) || listener == "*") { return true }
    return false
}

extension LocalSignals {
    var enabledServices: [ServiceFact] { services.filter { !$0.disabled } }

    var ethernetUp: Bool {
        enabledServices.contains { $0.kind == .ethernet && usableIPv4($0.ip) }
    }

    var linkUp: Bool {
        (wifi.associated && !wifi.powerOff) || ethernetUp
    }

    var tunnelExplained: Bool {
        !clients.isEmpty || vpn.contains(where: \.connected)
    }

    var utunDefaults: [DefaultRoute] {
        routes.filter { $0.interfaceName.hasPrefix("utun") }
    }

    var fakeIPTun: Bool {
        ifaces.contains { $0.name.hasPrefix("utun") && ($0.inet?.hasPrefix("198.18.") == true) }
    }

    var staleUtun: Bool {
        (!utunDefaults.isEmpty || fakeIPTun) && !tunnelExplained
    }

    var enabledProxies: [(service: String, label: String, proxy: ProxySetting)] {
        var found: [(String, String, ProxySetting)] = []
        for service in enabledServices {
            if let web = service.web, web.enabled { found.append((service.name, "HTTP", web)) }
            if let secure = service.secure, secure.enabled { found.append((service.name, "HTTPS", secure)) }
            if let socks = service.socks, socks.enabled { found.append((service.name, "SOCKS", socks)) }
        }
        return found
    }

    var deadLoopbackProxies: [(service: String, label: String, proxy: ProxySetting)] {
        enabledProxies.filter { isLoopback($0.proxy.server) && !isListening($0.proxy.server, $0.proxy.port, listeners) }
    }

    var allDNS: [String] {
        let fromServices = enabledServices.flatMap(\.dns)
        return unique(fromServices + dnsFromScutil)
    }

    var dnsHijackDead: Bool {
        allDNS.contains(where: isLoopback) && !isListening("127.0.0.1", 53, listeners)
    }

    var leftover: Bool {
        !deadLoopbackProxies.isEmpty || dnsHijackDead || staleUtun
    }

    var primaryGateway: String? {
        if let route = routes.first(where: { !$0.interfaceName.hasPrefix("utun") }) ?? routes.first {
            if route.gateway != "link#0" && !route.gateway.hasPrefix("link#") {
                return route.gateway
            }
        }
        return enabledServices.compactMap(\.router).first
    }

    var primaryIP: String? {
        if let wifi = enabledServices.first(where: { $0.kind == .wifi && usableIPv4($0.ip) }) {
            return wifi.ip
        }
        return enabledServices.compactMap(\.ip).first { usableIPv4($0) }
    }

    var campusSSID: Bool {
        let ssid = (wifi.ssid ?? "").lowercased()
        let keys = ["campus", "edu", "univ", "dorm", "校园", "大学"]
        return keys.contains { ssid.contains($0) }
    }

    var wpadOn: Bool {
        enabledServices.contains(where: \.wpad) || scutilProxy.wpadOn
    }
}
