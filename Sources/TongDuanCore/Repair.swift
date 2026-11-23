import Foundation

public enum RepairGuard {
    /// Free-form shell is never approved. Repairs only run as typed commands.
    public static func allowsUnstructuredShell(_ line: String) -> Bool {
        _ = line
        return false
    }

    public static func validate(_ command: RepairCommand, phase: RepairPhase, snapshot: RepairSnapshot?) throws {
        if command.isClash {
            try validateClash(command, phase: phase, snapshot: snapshot)
            return
        }
        let argv = argv(for: command)
        guard allowsArgv(argv, phase: phase, snapshot: snapshot) else {
            throw RepairError.forbidden(argv.joined(separator: " "))
        }
    }

    public static func allowsArgv(_ argv: [String], phase: RepairPhase, snapshot: RepairSnapshot?) -> Bool {
        guard let first = argv.first, argv.count >= 2 else { return false }
        if argv.contains(where: { token in
            token.contains(";") || token.contains("|") || token.contains("&") || token.contains("`")
                || token.contains("$") || token.contains("\n") || token.contains("\\")
        }) {
            return false
        }
        let blob = argv.joined(separator: " ").lowercased()
        let banned = [
            "socketfilterfw", "pfctl", "/etc/hosts", "keychain", "add-trusted-cert",
            "trusted-cert", "flush", "removepreferred", "uninstall", "setglobalstate",
            "delete", "profiles",
        ]
        if banned.contains(where: { blob.contains($0) }) { return false }

        switch first {
        case "/usr/sbin/networksetup":
            return allowNetworksetup(argv, phase: phase, snapshot: snapshot)
        case "/usr/sbin/ipconfig":
            guard argv.count == 4, argv[1] == "set", argv[3] == "DHCP", isPhysicalInterface(argv[2]) else { return false }
            return true
        case "/usr/sbin/scutil":
            guard argv == ["/usr/sbin/scutil", "--nc", argv.count > 2 ? argv[2] : "", argv.count > 3 ? argv[3] : ""] else {
                return false
            }
            guard argv.count == 4, argv[1] == "--nc", safeToken(argv[3]) else { return false }
            if argv[2] == "stop" { return phase == .repair || phase == .rollback }
            if argv[2] == "start" {
                return phase == .rollback && snapshot?.vpnConnected.contains(argv[3]) == true
            }
            return false
        default:
            return false
        }
    }

    public static func argv(for command: RepairCommand) -> [String] {
        switch command {
        case .setWebProxyState(let service, let enabled):
            return ["/usr/sbin/networksetup", "-setwebproxystate", service, enabled ? "on" : "off"]
        case .setSecureWebProxyState(let service, let enabled):
            return ["/usr/sbin/networksetup", "-setsecurewebproxystate", service, enabled ? "on" : "off"]
        case .setSocksProxyState(let service, let enabled):
            return ["/usr/sbin/networksetup", "-setsocksfirewallproxystate", service, enabled ? "on" : "off"]
        case .setAutoProxyState(let service, let enabled):
            return ["/usr/sbin/networksetup", "-setautoproxystate", service, enabled ? "on" : "off"]
        case .setProxyAutoDiscovery(let service, let enabled):
            return ["/usr/sbin/networksetup", "-setproxyautodiscovery", service, enabled ? "on" : "off"]
        case .setDNSServers(let service, let servers):
            if servers.isEmpty {
                return ["/usr/sbin/networksetup", "-setdnsservers", service, "Empty"]
            }
            return ["/usr/sbin/networksetup", "-setdnsservers", service] + servers
        case .renewDHCP(let interface):
            return ["/usr/sbin/ipconfig", "set", interface, "DHCP"]
        case .stopSystemVPN(let service):
            return ["/usr/sbin/scutil", "--nc", "stop", service]
        case .startSystemVPN(let service):
            return ["/usr/sbin/scutil", "--nc", "start", service]
        case .setWebProxy(let service, let host, let port):
            return ["/usr/sbin/networksetup", "-setwebproxy", service, host, String(port)]
        case .setSecureWebProxy(let service, let host, let port):
            return ["/usr/sbin/networksetup", "-setsecurewebproxy", service, host, String(port)]
        case .setSocksProxy(let service, let host, let port):
            return ["/usr/sbin/networksetup", "-setsocksfirewallproxy", service, host, String(port)]
        case .clashSetMode:
            return []
        }
    }
}

private func allowNetworksetup(_ argv: [String], phase: RepairPhase, snapshot: RepairSnapshot?) -> Bool {
    let verb = argv[1]
    switch verb {
    case "-setwebproxystate", "-setsecurewebproxystate", "-setsocksfirewallproxystate",
         "-setautoproxystate", "-setproxyautodiscovery":
        guard argv.count == 4, safeToken(argv[2]) else { return false }
        if argv[3] == "off" { return true }
        if argv[3] == "on" {
            return phase == .rollback && snapshotEnables(verb, service: argv[2], snapshot: snapshot)
        }
        return false
    case "-setdnsservers":
        guard argv.count >= 4, safeToken(argv[2]) else { return false }
        if argv.count == 4 && argv[3] == "Empty" { return true }
        guard phase == .rollback, let service = snapshot?.services.first(where: { $0.name == argv[2] }) else {
            return false
        }
        return Array(argv.dropFirst(3)) == service.dnsServers && !service.dnsServers.isEmpty
    case "-setwebproxy", "-setsecurewebproxy", "-setsocksfirewallproxy":
        guard phase == .rollback, argv.count == 5, safeToken(argv[2]), safeHost(argv[3]), let port = Int(argv[4]) else {
            return false
        }
        return snapshotHasProxy(verb, service: argv[2], host: argv[3], port: port, snapshot: snapshot)
    default:
        return false
    }
}

private func snapshotEnables(_ verb: String, service: String, snapshot: RepairSnapshot?) -> Bool {
    guard let item = snapshot?.services.first(where: { $0.name == service }) else { return false }
    switch verb {
    case "-setwebproxystate": return item.web?.enabled == true
    case "-setsecurewebproxystate": return item.secure?.enabled == true
    case "-setsocksfirewallproxystate": return item.socks?.enabled == true
    case "-setautoproxystate": return item.pacEnabled
    case "-setproxyautodiscovery": return item.wpad
    default: return false
    }
}

private func snapshotHasProxy(_ verb: String, service: String, host: String, port: Int, snapshot: RepairSnapshot?) -> Bool {
    guard let item = snapshot?.services.first(where: { $0.name == service }) else { return false }
    let endpoint: ProxyEndpoint?
    switch verb {
    case "-setwebproxy": endpoint = item.web
    case "-setsecurewebproxy": endpoint = item.secure
    case "-setsocksfirewallproxy": endpoint = item.socks
    default: endpoint = nil
    }
    guard let endpoint, endpoint.enabled, endpoint.server == host, endpoint.port == port else { return false }
    return true
}

private func validateClash(_ command: RepairCommand, phase: RepairPhase, snapshot: RepairSnapshot?) throws {
    guard case .clashSetMode(let host, let port, let mode) = command else {
        throw RepairError.forbidden("不是 Clash 命令")
    }
    guard isLoopback(host), (1...65535).contains(port), safeToken(mode) else {
        throw RepairError.forbidden("Clash API 必须已经在 127.0.0.1 上")
    }
    switch phase {
    case .repair:
        guard mode == "rule" else { throw RepairError.forbidden("修复时只允许把 Clash 从 global 改成 rule") }
    case .rollback:
        guard let saved = snapshot?.clashMode, mode == saved, ["rule", "global", "direct"].contains(mode) else {
            throw RepairError.forbidden("撤回 Clash 模式必须等于修复前的快照")
        }
        guard snapshot?.clashAPIHost.map(isLoopback) == true else {
            throw RepairError.forbidden("快照里的 Clash API 不是本机")
        }
    }
}

private func safeToken(_ value: String) -> Bool {
    if value.isEmpty || value.count > 120 || value.hasPrefix("-") { return false }
    let banned = CharacterSet(charactersIn: ";|&`$<>\n\r\\\"'*")
    return value.unicodeScalars.allSatisfy { scalar in
        !banned.contains(scalar) && !CharacterSet.controlCharacters.contains(scalar)
    }
}

private func safeHost(_ value: String) -> Bool {
    safeToken(value) && !value.contains("/") && !value.contains(" ")
}

private func isPhysicalInterface(_ name: String) -> Bool {
    if name.hasPrefix("en"), let suffix = Int(name.dropFirst(2)), suffix >= 0 { return true }
    if name.hasPrefix("bridge"), let suffix = Int(name.dropFirst("bridge".count)), suffix >= 0 { return true }
    return false
}

enum RepairPlanner {
    static func plan(_ s: LocalSignals, report: DiagnosisReport) -> RepairPlan {
        var items: [RepairItem] = []
        let failing = Set(report.hops.filter { $0.verdict == .duan || $0.verdict == .partial }.map(\.index))

        for service in s.enabledServices {
            let dead = [
                service.web.map { ("HTTP", $0) },
                service.secure.map { ("HTTPS", $0) },
                service.socks.map { ("SOCKS", $0) },
            ].compactMap { $0 }.filter { labelProxy in
                labelProxy.1.enabled && isLoopback(labelProxy.1.server) && !isListening(labelProxy.1.server, labelProxy.1.port, s.listeners)
            }
            if !dead.isEmpty {
                var commands: [RepairCommand] = []
                if service.web?.enabled == true && isLoopback(service.web?.server ?? "") {
                    commands.append(.setWebProxyState(service: service.name, enabled: false))
                }
                if service.secure?.enabled == true && isLoopback(service.secure?.server ?? "") {
                    commands.append(.setSecureWebProxyState(service: service.name, enabled: false))
                }
                if service.socks?.enabled == true && isLoopback(service.socks?.server ?? "") {
                    commands.append(.setSocksProxyState(service: service.name, enabled: false))
                }
                let current = dead.map { "\($0.0) \($0.1.server):\($0.1.port)" }.joined(separator: "；")
                let newer = dead.map { "\($0.0) 关闭" }.joined(separator: "；")
                items.append(RepairItem(
                    id: "clear-proxy-\(service.name)",
                    hop: 5,
                    title: "关闭 \(service.name) 上残留的本机代理",
                    currentValue: current,
                    newValue: newer,
                    risk: .safe,
                    commands: commands
                ))
            }
            if service.pacEnabled && s.leftover {
                let localPAC = (service.pacURL ?? "").contains("127.0.0.1") || (service.pacURL ?? "").contains("localhost")
                items.append(RepairItem(
                    id: "clear-pac-\(service.name)",
                    hop: 5,
                    title: "关闭 \(service.name) 的 PAC",
                    currentValue: service.pacURL ?? "PAC 开启",
                    newValue: "PAC 关闭",
                    risk: localPAC ? .safe : .high,
                    commands: [.setAutoProxyState(service: service.name, enabled: false)]
                ))
            }
            if service.wpad && s.leftover {
                items.append(RepairItem(
                    id: "clear-wpad-\(service.name)",
                    hop: 5,
                    title: "关闭 \(service.name) 的 WPAD",
                    currentValue: "WPAD 开启",
                    newValue: "WPAD 关闭",
                    risk: .high,
                    commands: [.setProxyAutoDiscovery(service: service.name, enabled: false)]
                ))
            }
        }

        if s.dnsHijackDead {
            for service in s.enabledServices where service.dns.contains(where: isLoopback) || service.dnsExplicitEmpty == false && s.dnsFromScutil.contains(where: isLoopback) {
                if service.dns.contains(where: isLoopback) {
                    items.append(RepairItem(
                        id: "clear-dns-\(service.name)",
                        hop: 4,
                        title: "清掉 \(service.name) 指向本机的 DNS",
                        currentValue: service.dns.joined(separator: "、"),
                        newValue: "清空，改回 DHCP 分配",
                        risk: .safe,
                        commands: [.setDNSServers(service: service.name, servers: [])]
                    ))
                }
            }
            if !items.contains(where: { $0.id.hasPrefix("clear-dns-") }) {
                if let service = s.enabledServices.first {
                    items.append(RepairItem(
                        id: "clear-dns-\(service.name)",
                        hop: 4,
                        title: "清掉 \(service.name) 上由系统解析器残留的本机 DNS",
                        currentValue: s.dnsFromScutil.joined(separator: "、"),
                        newValue: "清空，改回 DHCP 分配",
                        risk: .safe,
                        commands: [.setDNSServers(service: service.name, servers: [])]
                    ))
                }
            }
        }

        if failing.contains(2) {
            for service in s.enabledServices where service.method == "DHCP" && !usableIPv4(service.ip) {
                let interfaceIsUp: Bool
                if service.kind == .wifi {
                    interfaceIsUp = s.wifi.associated && !s.wifi.powerOff
                } else if service.kind == .ethernet {
                    interfaceIsUp = true
                } else {
                    interfaceIsUp = s.linkUp
                }
                if interfaceIsUp, let device = service.device, isPhysicalInterface(device) {
                    items.append(RepairItem(
                        id: "renew-\(device)",
                        hop: 2,
                        title: "向 \(device) 重新要一次 DHCP",
                        currentValue: service.ip ?? "没有地址",
                        newValue: "ipconfig set \(device) DHCP",
                        risk: .safe,
                        commands: [.renewDHCP(interface: device)]
                    ))
                }
            }
        }

        if s.staleUtun && !s.vpn.contains(where: \.connected) {
            items.append(RepairItem(
                id: "notice-no-route-flush",
                hop: 3,
                title: "不刷新路由表",
                currentValue: "utun 仍出现在默认路由或 198.18 网段",
                newValue: "保持不动。通不连禁止 route flush。请退出残留客户端后再检测。",
                risk: .high,
                commands: [],
                noticeOnly: true
            ))
        }

        if report.hop8 == .foreignPathDown {
            for vpn in s.vpn where vpn.connected {
                items.append(RepairItem(
                    id: "stop-vpn-\(vpn.name)",
                    hop: 6,
                    title: "断开系统 VPN「\(vpn.name)」",
                    currentValue: "已连接，不删除描述文件",
                    newValue: "断开连接。描述文件保留。",
                    risk: .high,
                    commands: [.stopSystemVPN(service: vpn.name)]
                ))
            }
            if let clash = s.clash, clash.mode == "global", isLoopback(clash.host) {
                items.append(RepairItem(
                    id: "clash-global-to-rule",
                    hop: 6,
                    title: "请 Clash 从 global 改成 rule",
                    currentValue: "mode = global（API \(clash.host):\(clash.port)）",
                    newValue: "mode = rule。只有本机 API 已经在听才会发。不会自动执行。",
                    risk: .high,
                    commands: [.clashSetMode(host: clash.host, port: clash.port, mode: "rule")]
                ))
            }
        }

        if items.isEmpty {
            return RepairPlan(items: [], headline: "这次没有要对着某一环下手的修复。检测本身没有改系统。")
        }
        return RepairPlan(
            items: items,
            headline: "下面是预览。安全项默认勾上，高风险项默认不勾。确认框一开始是空的。"
        )
    }

    static func snapshot(_ s: LocalSignals, now: Date) -> RepairSnapshot {
        let services = s.services.map { service in
            ServiceSnapshot(
                name: service.name,
                interfaceName: service.device,
                web: service.web.map { ProxyEndpoint(enabled: $0.enabled, server: $0.server, port: $0.port) },
                secure: service.secure.map { ProxyEndpoint(enabled: $0.enabled, server: $0.server, port: $0.port) },
                socks: service.socks.map { ProxyEndpoint(enabled: $0.enabled, server: $0.server, port: $0.port) },
                pacEnabled: service.pacEnabled,
                pacURL: service.pacURL,
                wpad: service.wpad,
                dnsServers: service.dns,
                dnsWasEmpty: service.dnsExplicitEmpty || service.dns.isEmpty
            )
        }
        return RepairSnapshot(
            takenAt: now,
            services: services,
            vpnConnected: s.vpn.filter(\.connected).map(\.name),
            clashMode: s.clash?.mode,
            clashAPIHost: s.clash?.host,
            clashAPIPort: s.clash?.port
        )
    }

    static func rollbackCommands(_ snapshot: RepairSnapshot) -> [RepairCommand] {
        var commands: [RepairCommand] = []
        for service in snapshot.services {
            commands.append(contentsOf: restore(service.web, service: service.name, kind: .web))
            commands.append(contentsOf: restore(service.secure, service: service.name, kind: .secure))
            commands.append(contentsOf: restore(service.socks, service: service.name, kind: .socks))
            commands.append(.setAutoProxyState(service: service.name, enabled: service.pacEnabled))
            commands.append(.setProxyAutoDiscovery(service: service.name, enabled: service.wpad))
            if service.dnsWasEmpty || service.dnsServers.isEmpty {
                commands.append(.setDNSServers(service: service.name, servers: []))
            } else {
                commands.append(.setDNSServers(service: service.name, servers: service.dnsServers))
            }
        }
        for name in snapshot.vpnConnected {
            commands.append(.startSystemVPN(service: name))
        }
        if let mode = snapshot.clashMode, let host = snapshot.clashAPIHost, let port = snapshot.clashAPIPort {
            commands.append(.clashSetMode(host: host, port: port, mode: mode))
        }
        return commands
    }
}

private enum ProxyKind { case web, secure, socks }

private func restore(_ endpoint: ProxyEndpoint?, service: String, kind: ProxyKind) -> [RepairCommand] {
    guard let endpoint else {
        switch kind {
        case .web: return [.setWebProxyState(service: service, enabled: false)]
        case .secure: return [.setSecureWebProxyState(service: service, enabled: false)]
        case .socks: return [.setSocksProxyState(service: service, enabled: false)]
        }
    }
    if endpoint.enabled && !endpoint.server.isEmpty && endpoint.port > 0 {
        switch kind {
        case .web:
            return [
                .setWebProxy(service: service, host: endpoint.server, port: endpoint.port),
                .setWebProxyState(service: service, enabled: true),
            ]
        case .secure:
            return [
                .setSecureWebProxy(service: service, host: endpoint.server, port: endpoint.port),
                .setSecureWebProxyState(service: service, enabled: true),
            ]
        case .socks:
            return [
                .setSocksProxy(service: service, host: endpoint.server, port: endpoint.port),
                .setSocksProxyState(service: service, enabled: true),
            ]
        }
    }
    switch kind {
    case .web: return [.setWebProxyState(service: service, enabled: false)]
    case .secure: return [.setSecureWebProxyState(service: service, enabled: false)]
    case .socks: return [.setSocksProxyState(service: service, enabled: false)]
    }
}

public func planRepairs(_ bundle: ProbeBundle, report: DiagnosisReport) -> RepairPlan {
    RepairPlanner.plan(Parser.parse(bundle), report: report)
}

public func makeSnapshot(_ bundle: ProbeBundle, now: Date = Date()) -> RepairSnapshot {
    RepairPlanner.snapshot(Parser.parse(bundle), now: now)
}

public func rollbackCommands(for snapshot: RepairSnapshot) -> [RepairCommand] {
    RepairPlanner.rollbackCommands(snapshot)
}
