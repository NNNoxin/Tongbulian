import Foundation

public func diagnose(_ bundle: ProbeBundle, now: Date = Date()) -> DiagnosisReport {
    let signals = Parser.parse(bundle)
    let classified = Classify.hops(signals)
    let path = Classify.path(signals)
    let diagram = DiagramBuilder.build(signals, model: path.model, footnote: path.footnote)
    let conflict = Classify.conflict(for: path.model)
    let observation = observe(signals, model: path.model)
    return DiagnosisReport(
        generatedAt: now,
        scope: bundle.scope,
        hops: classified.hops,
        pathModel: path.model,
        pathFootnote: path.footnote,
        diagram: diagram,
        conflict: conflict,
        hop8: classified.hop8,
        observation: observation,
        collectorNotes: signals.notes
    )
}

private func observe(_ s: LocalSignals, model: PathModel) -> NetworkObservation {
    let linkKind: String
    if s.wifi.associated && !s.wifi.powerOff && s.ethernetUp {
        linkKind = "Wi-Fi+以太网"
    } else if s.wifi.associated && !s.wifi.powerOff {
        linkKind = "Wi-Fi"
    } else if s.ethernetUp {
        linkKind = "以太网"
    } else if s.wifi.powerOff {
        linkKind = "Wi-Fi 关闭"
    } else {
        linkKind = "无"
    }
    let proxy = s.enabledProxies.first
    let clientNames = s.clients.map(\.brand.rawValue)
    let vpnNames = s.vpn.filter(\.connected).map(\.name)
    let vpnClient = (clientNames + vpnNames).isEmpty ? nil : (clientNames + vpnNames).joined(separator: "、")
    let tunnelAddress = s.ifaces.first { $0.name.hasPrefix("utun") && $0.inet != nil }?.inet
        ?? s.utunDefaults.first?.gateway
    return NetworkObservation(
        linkKind: linkKind,
        linkUp: s.linkUp,
        ssid: s.wifi.ssid,
        ip: s.primaryIP,
        gateway: s.primaryGateway,
        dns: s.allDNS,
        systemProxyOn: proxy != nil,
        systemProxyHost: proxy?.proxy.server,
        systemProxyPort: proxy?.proxy.port,
        vpnClient: vpnClient,
        tunnelAddress: tunnelAddress,
        pathModel: model
    )
}
