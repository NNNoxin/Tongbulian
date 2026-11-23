import Foundation

enum DiagramBuilder {
    static func build(_ s: LocalSignals, model: PathModel, footnote: String) -> PathDiagram {
        let link = linkNode(s)
        let gateway = DiagramNode(
            id: "gateway",
            title: "网关",
            detail: s.primaryGateway ?? "没有",
            tone: s.gatewayProbeOK == false ? .bad : (s.gatewayProbeOK == true ? .ok : .muted),
            row: 2,
            column: 0
        )
        let dnsServers = s.allDNS
        let dns = DiagramNode(
            id: "dns",
            title: "DNS",
            detail: dnsServers.isEmpty ? "没有" : dnsServers.joined(separator: " "),
            tone: s.dnsHijackDead ? .bad : (dnsServers.isEmpty ? .warn : .info),
            row: 1,
            column: 1
        )
        var nodes: [DiagramNode] = [
            DiagramNode(id: "mac", title: "本机", detail: "通不连", tone: .info, row: 0, column: 0),
            link,
            dns,
            gateway,
            DiagramNode(id: "domestic", title: "境内", detail: "baidu 直连", tone: domesticTone(s), row: 3, column: 0),
            DiagramNode(id: "foreign", title: "境外", detail: "同一目标 443", tone: foreignTone(s), row: 3, column: 1),
        ]
        if let proxy = s.enabledProxies.first {
            nodes.append(
                DiagramNode(
                    id: "proxy",
                    title: "系统代理",
                    detail: "\(proxy.proxy.server):\(proxy.proxy.port)",
                    tone: isLoopback(proxy.proxy.server) && !isListening(proxy.proxy.server, proxy.proxy.port, s.listeners) ? .bad : .warn,
                    row: 1,
                    column: 2
                )
            )
        }
        if !s.clients.isEmpty || s.vpn.contains(where: \.connected) || !s.utunDefaults.isEmpty {
            let name = s.clients.map(\.brand.rawValue).joined(separator: " / ")
            let vpn = s.vpn.filter(\.connected).map(\.name).joined(separator: " / ")
            let title = !name.isEmpty ? name : (!vpn.isEmpty ? vpn : "utun")
            let detail = s.clash?.mode.map { "模式 \($0)" } ?? (s.utunDefaults.first.map { $0.interfaceName } ?? "隧道")
            nodes.append(DiagramNode(id: "tunnel", title: title, detail: detail, tone: s.staleUtun ? .bad : .info, row: 2, column: 1))
        }

        let domesticInferred = s.scope == .local || s.domesticDirectOK == nil
        let gatewayInferred = s.gatewayProbeOK == nil
        var edges: [DiagramEdge] = [
            DiagramEdge(id: "e-link", from: "mac", to: "link", label: s.linkUp ? "已连接" : "未连接", inferred: false, tone: s.linkUp ? .ok : .bad),
            DiagramEdge(id: "e-gw", from: "link", to: "gateway", label: "下一跳", inferred: gatewayInferred, tone: gatewayInferred ? .muted : (s.gatewayProbeOK == false ? .bad : .ok)),
            DiagramEdge(id: "e-dns", from: "mac", to: "dns", label: "解析", inferred: false, tone: s.dnsHijackDead ? .bad : .info),
            DiagramEdge(id: "e-dom", from: "gateway", to: "domestic", label: "境内直连", inferred: domesticInferred, tone: domesticInferred ? .muted : domesticTone(s)),
        ]
        if nodes.contains(where: { $0.id == "proxy" }) {
            edges.append(DiagramEdge(id: "e-proxy", from: "mac", to: "proxy", label: "系统代理", inferred: false, tone: .warn))
            if nodes.contains(where: { $0.id == "tunnel" }) {
                edges.append(DiagramEdge(id: "e-client", from: "proxy", to: "tunnel", label: "本地客户端", inferred: false, tone: .info))
                edges.append(DiagramEdge(id: "e-via", from: "tunnel", to: "foreign", label: "经隧道", inferred: s.foreignViaTunnelOK == nil, tone: s.foreignViaTunnelOK == false ? .bad : .info))
            } else {
                edges.append(DiagramEdge(id: "e-proxy-foreign", from: "proxy", to: "foreign", label: "经代理", inferred: s.foreignViaTunnelOK == nil, tone: .warn))
            }
        } else if nodes.contains(where: { $0.id == "tunnel" }) {
            edges.append(DiagramEdge(id: "e-tun", from: "mac", to: "tunnel", label: model == .splitTunnel ? "拆分" : "隧道", inferred: false, tone: s.staleUtun ? .bad : .info))
            edges.append(DiagramEdge(id: "e-via", from: "tunnel", to: "foreign", label: model == .splitTunnel ? "仅隧道网段" : "经隧道", inferred: s.foreignViaTunnelOK == nil || model == .splitTunnel, tone: .info))
        }
        if model == .directClean || model == .splitTunnel || model == .ruleSplit || model == .campusMixed {
            edges.append(DiagramEdge(id: "e-foreign-direct", from: "gateway", to: "foreign", label: "境外直连", inferred: s.foreignDirectOK == nil || s.scope == .local, tone: s.foreignDirectOK == false ? .warn : .muted))
        }
        if model == .tunGlobal {
            edges.append(DiagramEdge(id: "e-captured", from: "mac", to: "foreign", label: "全局", inferred: s.foreignViaTunnelOK == nil, tone: .warn))
        }

        var footnotes = [footnote, "虚线是推断，不是测到的。"]
        if s.scope == .local {
            footnotes.append("局部检测不探测境内和境外，那两条边都是推断。")
        }
        return PathDiagram(model: model, nodes: nodes, edges: edges, footnotes: footnotes)
    }
}

private func linkNode(_ s: LocalSignals) -> DiagramNode {
    if s.wifi.associated && !s.wifi.powerOff {
        let rssi = s.wifi.rssi.map { " \($0) dBm" } ?? ""
        return DiagramNode(id: "link", title: "Wi-Fi", detail: (s.wifi.ssid ?? "已关联") + rssi, tone: (s.wifi.rssi ?? 0) <= -80 && s.wifi.rssi != nil ? .warn : .ok, row: 1, column: 0)
    }
    if s.ethernetUp {
        return DiagramNode(id: "link", title: "以太网", detail: s.primaryIP ?? "已连接", tone: .ok, row: 1, column: 0)
    }
    if s.wifi.powerOff {
        return DiagramNode(id: "link", title: "Wi-Fi", detail: "已关闭", tone: .bad, row: 1, column: 0)
    }
    return DiagramNode(id: "link", title: "物理链路", detail: "未连接", tone: .bad, row: 1, column: 0)
}

private func domesticTone(_ s: LocalSignals) -> Tone {
    switch s.domesticDirectOK {
    case true: return .ok
    case false: return .bad
    case nil: return .muted
    }
}

private func foreignTone(_ s: LocalSignals) -> Tone {
    if s.foreignViaTunnelOK == false || s.foreignDirectOK == false { return .warn }
    if s.foreignViaTunnelOK == true || s.foreignDirectOK == true { return .ok }
    return .muted
}
