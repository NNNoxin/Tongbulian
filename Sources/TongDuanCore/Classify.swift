import Foundation

enum Classify {
    static func hops(_ s: LocalSignals) -> (hops: [HopResult], hop8: Hop8Assessment) {
        if !s.hasEvidence {
            let gap = "没有采集到网卡、路由或 Wi-Fi 输出，不能判断这台 Mac 的网络。"
            let hops = (1...8).map { index in
                HopResult(
                    index: index,
                    title: hopTitle(index),
                    verdict: .unknown,
                    summary: "没有本机证据",
                    evidence: ["采集结果是空的"],
                    informationGap: gap
                )
            }
            return (hops, s.scope == .local ? .notRun : .informationGap)
        }
        let eighth = hop8(s)
        return ([hop1(s), hop2(s), hop3(s), hop4(s), hop5(s), hop6(s), hop7(s), eighth.result], eighth.assessment)
    }

    static func path(_ s: LocalSignals) -> (model: PathModel, footnote: String) {
        if !s.hasEvidence {
            return (.unknown, "没有足够的本机信号，路径模型标成未知。")
        }
        if s.leftover {
            return (.stale, leftoverFootnote(s))
        }
        if isCampus(s) && campusRelevant(s) {
            return (.campusMixed, "校园网标记和代理或隧道叠在一起。图里两条路都画出来，通不连不会替你选一条。")
        }
        if isTunGlobal(s) {
            if s.clash?.mode == "global", s.utunDefaults.isEmpty {
                return (.tunGlobal, "Clash 模式是 global。默认路由仍在物理网卡，这是全局代理，不一定是 TUN。")
            }
            if s.clash?.tun == true || !s.utunDefaults.isEmpty {
                return (.tunGlobal, "默认流量进了 utun，或客户端打开了 TUN。这是全局隧道，不是只改了系统代理。")
            }
            return (.tunGlobal, "当前信号更接近 TUN / 全局。")
        }
        if isRuleSplit(s) {
            return (.ruleSplit, "客户端在跑规则模式，默认路由仍走物理网卡。国内和境外可以走不同的路。")
        }
        if hasLiveSystemProxy(s) {
            return (.systemProxy, "系统代理开着，而且本地端口或外部代理地址有记录。没有发现 TUN 接管默认路由。")
        }
        if isSplitTunnel(s) {
            return (.splitTunnel, "VPN 或 Tailscale 在线，但默认路由还在物理网卡。没进隧道的流量会直连。")
        }
        return (.directClean, "没有系统代理，没有接管默认路由的隧道，也没有残留的 127.0.0.1 指向。")
    }

    static func conflict(for model: PathModel) -> AppConflictNote {
        let refusal = "通不连只把冲突写出来，不会自动切换代理模式，也不会把全局改成规则。"
        switch model {
        case .directClean:
            return AppConflictNote(
                workBuddy: "WorkBuddy 需要大陆直连。当前是直连，国内流量不进隧道。",
                claudeAndChatGPT: "Claude / ChatGPT 通常希望走 TUN 或全局，避免直连泄漏。当前没有这条隧道。",
                willAutoSwitch: false,
                refusal: refusal
            )
        case .systemProxy:
            return AppConflictNote(
                workBuddy: "WorkBuddy 需要大陆直连。系统代理如果没有国内绕过，国内站点也会进代理。",
                claudeAndChatGPT: "系统代理盖不住所有进程。Claude / ChatGPT 更常见的要求是 TUN / 全局，而不是只改浏览器代理。",
                willAutoSwitch: false,
                refusal: refusal
            )
        case .tunGlobal:
            return AppConflictNote(
                workBuddy: "WorkBuddy 需要大陆直连。TUN / 全局会把国内流量也送进隧道，它可能变慢或打不开。",
                claudeAndChatGPT: "Claude / ChatGPT 这种怕泄漏的用法，通常希望走 TUN / 全局。当前路径和这个预期一致。",
                willAutoSwitch: false,
                refusal: refusal
            )
        case .ruleSplit:
            return AppConflictNote(
                workBuddy: "WorkBuddy 需要大陆直连。规则里如果国内域名直连，它可以用。",
                claudeAndChatGPT: "规则没盖住的连接可能直连出去。Claude / ChatGPT 更常要求 TUN / 全局。",
                willAutoSwitch: false,
                refusal: refusal
            )
        case .splitTunnel:
            return AppConflictNote(
                workBuddy: "默认路由仍是直连，WorkBuddy 要的大陆出口还在。拆分隧道里的网段另算。",
                claudeAndChatGPT: "没进隧道的流量会直连。对怕泄漏的 Claude / ChatGPT，这通常不够。",
                willAutoSwitch: false,
                refusal: refusal
            )
        case .stale:
            return AppConflictNote(
                workBuddy: "残留代理或 DNS 会让国内直连也不可靠。WorkBuddy 需要的大陆出口目前不能当真。",
                claudeAndChatGPT: "残留的 127.0.0.1 或 utun 不是一条干净的 TUN / 全局，也不能当成已经配好的代理。",
                willAutoSwitch: false,
                refusal: refusal
            )
        case .campusMixed:
            return AppConflictNote(
                workBuddy: "校园网策略和代理叠在一起。WorkBuddy 仍然需要一条真正的大陆直连。",
                claudeAndChatGPT: "校园网出口通常到不了 Claude / ChatGPT。要不要改成 TUN / 全局由你决定。",
                willAutoSwitch: false,
                refusal: refusal
            )
        case .unknown:
            return AppConflictNote(
                workBuddy: "路径还没判断出来，不能说 WorkBuddy 现在走的是大陆直连。",
                claudeAndChatGPT: "路径还没判断出来，不能说 Claude / ChatGPT 已经进了 TUN / 全局。",
                willAutoSwitch: false,
                refusal: refusal
            )
        }
    }
}

private func hopTitle(_ index: Int) -> String {
    switch index {
    case 1: return "物理链路"
    case 2: return "地址与 DHCP"
    case 3: return "默认路由"
    case 4: return "DNS"
    case 5: return "系统代理"
    case 6: return "VPN 与隧道"
    case 7: return "本地连通"
    default: return "目标连通"
    }
}

private func hop(
    _ index: Int,
    _ verdict: HopVerdict,
    _ summary: String,
    _ evidence: [String],
    inferred: Bool = false,
    gap: String? = nil
) -> HopResult {
    HopResult(
        index: index,
        title: hopTitle(index),
        verdict: verdict,
        summary: summary,
        evidence: evidence,
        inferred: inferred,
        informationGap: gap
    )
}

private func hop1(_ s: LocalSignals) -> HopResult {
    var evidence: [String] = []
    if s.wifi.hardwarePresent {
        evidence.append("硬件口有 Wi-Fi\(s.wifi.interfaceName.map { "（\($0)）" } ?? "")")
    } else {
        evidence.append("硬件口列表里没有 Wi-Fi")
    }
    if s.ethernetUp {
        let ips = s.enabledServices.filter { $0.kind == .ethernet && usableIPv4($0.ip) }.map { "\($0.name) \($0.ip ?? "")" }
        evidence.append("以太网已有地址 \(ips.joined(separator: "、"))")
    } else {
        evidence.append("以太网没有可用 IPv4")
    }
    if !s.wifi.stateKnown && s.wifi.hardwarePresent && !s.ethernetUp {
        evidence.append("没有 Wi-Fi 关联输出")
        return hop(1, .unknown, "Wi-Fi 状态没采集到，以太网也没有地址", evidence, gap: "缺少 airport / CoreWLAN 输出，物理链路标为未知。")
    }
    if s.wifi.powerOff && !s.ethernetUp {
        evidence.append("Wi-Fi 电源关闭")
        return hop(1, .duan, "Wi-Fi 已关闭，以太网也没有可用地址", evidence)
    }
    if s.wifi.powerOff && s.ethernetUp {
        evidence.append("Wi-Fi 电源关闭")
        return hop(1, .tong, "以太网已连接，Wi-Fi 关闭", evidence)
    }
    if s.wifi.associated {
        evidence.append("已关联 \(s.wifi.ssid ?? "未读到 SSID")")
        if let rssi = s.wifi.rssi {
            evidence.append("RSSI \(rssi) dBm")
            if rssi <= -80 {
                let name = s.wifi.ssid ?? "当前网络"
                return hop(1, .partial, "Wi-Fi 已关联 \(name)，但信号弱（\(rssi) dBm）", evidence)
            }
        } else {
            evidence.append("没有 RSSI，信号强弱是信息缺口")
        }
        let name = s.wifi.ssid.map { "Wi-Fi 已关联 \($0)" } ?? "Wi-Fi 已关联"
        if s.ethernetUp {
            return hop(1, .tong, "\(name)，以太网也在线", evidence)
        }
        return hop(1, .tong, name, evidence)
    }
    if s.wifi.hardwarePresent && !s.ethernetUp {
        evidence.append("Wi-Fi 未关联")
        return hop(1, .duan, "Wi-Fi 未关联，以太网也没有地址", evidence)
    }
    if s.ethernetUp {
        return hop(1, .tong, "以太网已连接", evidence)
    }
    return hop(1, .unknown, "看不出哪块网卡是通的", evidence, gap: "物理链路证据不足。")
}

private func hop2(_ s: LocalSignals) -> HopResult {
    let enabled = s.enabledServices
    if enabled.isEmpty {
        return hop(2, .duan, "没有启用的网络服务", ["网络服务列表里没有启用项"])
    }
    if enabled.contains(where: \.infoMissing) && enabled.allSatisfy({ $0.ip == nil }) {
        return hop(2, .unknown, "没有读到地址信息", enabled.map { "\($0.name)：缺少 networksetup -getinfo" }, gap: "地址与 DHCP 输出缺失。")
    }
    let good = enabled.filter { usableIPv4($0.ip) }
    if !good.isEmpty {
        let evidence = good.map { service in
            "\(service.name)：\(service.method) \(service.ip ?? "")，网关 \(service.router ?? "无")"
        }
        let first = good[0]
        return hop(2, .tong, "\(first.name) \(first.method) \(first.ip ?? "")", evidence)
    }
    let linkLocal = enabled.filter { isLinkLocal($0.ip) }
    if !linkLocal.isEmpty {
        let evidence = linkLocal.map { "\($0.name)：\($0.ip ?? "")（169.254 链路本地）" }
        return hop(2, .duan, "只有 169.254 链路本地地址，DHCP 没有成功", evidence)
    }
    let dhcpMiss = enabled.filter { $0.method == "DHCP" && $0.ip == nil }
    if !dhcpMiss.isEmpty {
        return hop(2, .duan, "DHCP 没有发到地址", dhcpMiss.map { "\($0.name)：DHCP，IP 为空" })
    }
    return hop(2, .duan, "启用的网络服务都没有可用 IPv4", enabled.map { "\($0.name)：\( $0.ip ?? "无地址")" })
}

private func hop3(_ s: LocalSignals) -> HopResult {
    if s.routes.isEmpty {
        if s.routeFailed || s.sawRouteOutput {
            return hop(3, .duan, "没有默认路由", ["route / netstat 里看不到 default"])
        }
        return hop(3, .unknown, "没有路由表输出", ["route 与 netstat 都是空的"], gap: "默认路由没有采集到。")
    }
    let described = s.routes.map { "default → \($0.gateway) \($0.interfaceName)" }
    if s.routes.count > 1 {
        return hop(3, .partial, "有 \(s.routes.count) 条默认路由", described)
    }
    let route = s.routes[0]
    if route.interfaceName.hasPrefix("utun"), !s.tunnelExplained {
        return hop(3, .partial, "默认路由指向 \(route.interfaceName)，但没有对应的隧道进程", described, inferred: true)
    }
    return hop(3, .tong, "默认路由 \(route.gateway) 经由 \(route.interfaceName)", described)
}

private func hop4(_ s: LocalSignals) -> HopResult {
    let serviceDNS = unique(s.enabledServices.flatMap(\.dns))
    let scutil = s.dnsFromScutil
    let combined = unique(serviceDNS + scutil)
    var evidence: [String] = []
    if serviceDNS.isEmpty {
        let explicit = s.enabledServices.contains(where: \.dnsExplicitEmpty)
        evidence.append(explicit ? "网络服务没有手动指定 DNS" : "网络服务 DNS 输出为空")
    } else {
        evidence.append("网络服务 DNS：\(serviceDNS.joined(separator: "、"))")
    }
    evidence.append(scutil.isEmpty ? "scutil --dns 没有 nameserver" : "scutil --dns：\(scutil.joined(separator: "、"))")

    if s.enabledServices.allSatisfy(\.dnsMissing) && scutil.isEmpty && s.scutilProxy.httpHost.isEmpty && combined.isEmpty {
        let anyDNSText = s.enabledServices.contains { !$0.dnsMissing } || !scutil.isEmpty
        if !anyDNSText && s.notes.isEmpty {
            // Still a real empty DNS if the service text said so. dnsMissing means the field was blank.
        }
    }
    let sawDNS = s.enabledServices.contains { !$0.dnsMissing } || !s.dnsFromScutil.isEmpty || s.enabledServices.contains(where: \.dnsExplicitEmpty)
    if !sawDNS {
        return hop(4, .unknown, "没有 DNS 输出", evidence, gap: "没有 getdnsservers，也没有 scutil --dns。")
    }
    if combined.contains(where: { $0 == "0.0.0.0" || $0 == "255.255.255.255" }) {
        return hop(4, .duan, "DNS 地址无效", evidence)
    }
    if combined.contains(where: isLoopback) {
        if s.dnsHijackDead {
            return hop(4, .duan, "DNS 指向 127.0.0.1，但没有进程监听 53", evidence + ["本机 53 端口没有监听"])
        }
        return hop(4, .tong, "DNS 被本机接管，53 端口有进程在听", evidence + ["这是本地 DNS 劫持，而且进程还在"])
    }
    if combined.isEmpty {
        return hop(4, .duan, "没有读到可用 DNS", evidence)
    }
    if serviceDNS.isEmpty && !scutil.isEmpty {
        return hop(4, .tong, "使用 DHCP / 系统解析器 \(scutil.joined(separator: "、"))", evidence)
    }
    if !serviceDNS.isEmpty && !scutil.isEmpty && Set(serviceDNS) != Set(scutil) {
        return hop(4, .partial, "网络服务里的 DNS 和 scutil 不一致", evidence)
    }
    return hop(4, .tong, "DNS：\(combined.joined(separator: "、"))", evidence)
}

private func hop5(_ s: LocalSignals) -> HopResult {
    var evidence: [String] = []
    var rank = 0 // 0 tong, 1 unknown, 2 partial, 3 duan
    func bump(_ verdict: HopVerdict) {
        let value: Int
        switch verdict {
        case .tong: value = 0
        case .unknown: value = 1
        case .partial: value = 2
        case .duan: value = 3
        }
        if value > rank { rank = value }
    }
    if s.services.isEmpty {
        return hop(5, .unknown, "没有网络服务列表", ["无法逐个服务核对代理"], gap: "系统代理这一环缺少 networksetup 输出。")
    }
    for service in s.services {
        var bits: [String] = []
        if service.proxyMissing {
            bits.append("没有采集到 HTTP/HTTPS/SOCKS")
            if !service.disabled { bump(.unknown) }
        } else {
            let proxies: [(String, ProxySetting?)] = [("HTTP", service.web), ("HTTPS", service.secure), ("SOCKS", service.socks)]
            var anyOn = false
            for (label, setting) in proxies {
                guard let setting, setting.enabled else { continue }
                anyOn = true
                if isLoopback(setting.server) {
                    if isListening(setting.server, setting.port, s.listeners) {
                        bits.append("\(label) \(setting.server):\(setting.port) 有进程监听")
                    } else {
                        bits.append("\(label) \(setting.server):\(setting.port) 已开启，但没有进程监听")
                        bump(service.disabled ? .partial : .duan)
                    }
                } else if setting.server.isEmpty || setting.port == 0 {
                    bits.append("\(label) 显示开启，但服务器或端口是空的")
                    bump(service.disabled ? .partial : .duan)
                } else {
                    bits.append("\(label) 指向外部 \(setting.server):\(setting.port)，通不连不去验证这台外部代理")
                    bump(.partial)
                }
            }
            if !anyOn {
                bits.append("HTTP / HTTPS / SOCKS 均关闭")
            }
        }
        if service.pacEnabled {
            bits.append("PAC \(service.pacURL ?? "已开启，没有 URL")。通不连不执行 PAC 脚本")
            bump(.partial)
        }
        if service.wpad {
            bits.append("WPAD 自动发现开启")
            bump(.partial)
        }
        let prefix = service.disabled ? "\(service.name)（已停用）" : service.name
        evidence.append(prefix + "：" + bits.joined(separator: "；"))
        if service.disabled && proxyEnabled(service) {
            bump(.partial)
        }
    }
    if scutilDisagrees(s) {
        evidence.append("scutil --proxy 和 networksetup 的开关不一致")
        bump(.partial)
    }
    let verdict: HopVerdict
    let summary: String
    switch rank {
    case 3:
        verdict = .duan
        summary = "有网络服务的系统代理指向本机，但没有进程在听"
    case 2:
        verdict = .partial
        summary = "系统代理并不干净，详见每个网络服务"
    case 1:
        verdict = .unknown
        summary = "有网络服务缺少代理采集"
    default:
        verdict = .tong
        if s.enabledProxies.isEmpty {
            summary = "检查过的网络服务都没有启用 HTTP / HTTPS / SOCKS"
        } else {
            summary = "系统代理开着，对应的本机端口有进程监听"
        }
    }
    let gap = rank == 1 ? "部分网络服务没有代理输出。" : nil
    return hop(5, verdict, summary, evidence, gap: gap)
}

private func proxyEnabled(_ service: ServiceFact) -> Bool {
    (service.web?.enabled ?? false) || (service.secure?.enabled ?? false) || (service.socks?.enabled ?? false)
}

private func scutilDisagrees(_ s: LocalSignals) -> Bool {
    let anyHTTP = s.enabledServices.contains { $0.web?.enabled == true }
    let anyHTTPS = s.enabledServices.contains { $0.secure?.enabled == true }
    let anySOCKS = s.enabledServices.contains { $0.socks?.enabled == true }
    if s.scutilProxy.httpOn != anyHTTP && (s.scutilProxy.httpOn || anyHTTP) { return true }
    if s.scutilProxy.httpsOn != anyHTTPS && (s.scutilProxy.httpsOn || anyHTTPS) { return true }
    if s.scutilProxy.socksOn != anySOCKS && (s.scutilProxy.socksOn || anySOCKS) { return true }
    return false
}

private func hop6(_ s: LocalSignals) -> HopResult {
    var evidence: [String] = []
    if s.clients.isEmpty {
        evidence.append("进程列表里没有 Clash、Clash Verge、Surge、WireGuard、sing-box、V2Ray、Tailscale、AnyConnect、aTrust、OpenVPN")
    } else {
        evidence.append("客户端：" + s.clients.map(\.brand.rawValue).joined(separator: "、"))
    }
    if s.vpn.isEmpty {
        evidence.append("scutil --nc 没有系统 VPN 条目")
    } else {
        for item in s.vpn {
            evidence.append("系统 VPN「\(item.name)」\(item.connected ? "已连接" : "未连接") \(item.kind)")
        }
    }
    var gap: String?
    if let clash = s.clash {
        let mode = clash.mode ?? "未知"
        let tun = clash.tun == true ? "开" : (clash.tun == false ? "关" : "未知")
        evidence.append("Clash API \(clash.host):\(clash.port) 已响应，模式 \(mode)，TUN \(tun)")
    } else if s.clients.contains(where: { $0.brand == .clash || $0.brand == .clashVerge }) {
        evidence.append("Clash 进程在，但 127.0.0.1 上的外部控制器没有返回配置")
        gap = "不知道 Clash 是 rule、global 还是 direct。通不连不会去读配置文件或猜密钥。"
    }
    if s.staleUtun {
        let ifaces = s.utunDefaults.map(\.interfaceName).joined(separator: "、")
        evidence.append("utun 仍在路由里（\(ifaces.isEmpty ? "198.18 网段" : ifaces)），对应客户端或系统 VPN 不在")
        return hop(6, .duan, "隧道进程已经不在，utun 路由还留着", evidence)
    }
    let proxyStacks = s.clients.filter {
        switch $0.brand {
        case .clash, .clashVerge, .surge, .singBox, .v2ray, .wireguard:
            return true
        default:
            return false
        }
    }
    if proxyStacks.count >= 2 {
        return hop(6, .partial, "同时发现多个代理客户端", evidence, gap: gap)
    }
    if s.clients.isEmpty && !s.vpn.contains(where: \.connected) {
        return hop(6, .tong, "没有发现正在运行的 VPN 或代理客户端", evidence)
    }
    let names = s.clients.map(\.brand.rawValue) + s.vpn.filter(\.connected).map { "系统 VPN \($0.name)" }
    if gap != nil {
        return hop(6, .partial, names.joined(separator: "、") + " 在运行，模式有信息缺口", evidence, gap: gap)
    }
    if s.clients.contains(where: { $0.brand == .tailscale }), s.utunDefaults.isEmpty {
        evidence.append("Tailscale 没有拿走默认路由，按拆分隧道理解")
    }
    return hop(6, .tong, names.joined(separator: "、") + " 在运行", evidence)
}

private func hop7(_ s: LocalSignals) -> HopResult {
    var evidence: [String] = []
    var verdict: HopVerdict = .tong
    var inferred = false
    var gap: String?
    if let gateway = s.primaryGateway {
        evidence.append("下一跳 \(gateway)")
        switch s.gatewayProbeOK {
        case true:
            evidence.append(s.gatewayProbeDetail.isEmpty ? "网关探测成功" : s.gatewayProbeDetail)
        case false:
            evidence.append(s.gatewayProbeDetail.isEmpty ? "网关探测失败" : s.gatewayProbeDetail)
            verdict = .duan
        case nil:
            evidence.append("没有实际探测网关，只在路由或 DHCP 里看到下一跳")
            verdict = .partial
            inferred = true
            gap = "网关可达性是推断，不是测量。"
        }
    } else {
        evidence.append("没有网关地址")
        verdict = .duan
    }
    if s.enabledProxies.isEmpty {
        evidence.append("没有需要核对的本地代理端口")
    } else {
        for item in s.enabledProxies where isLoopback(item.proxy.server) {
            if isListening(item.proxy.server, item.proxy.port, s.listeners) {
                evidence.append("\(item.service) \(item.label) \(item.proxy.server):\(item.proxy.port) 正在监听")
            } else {
                evidence.append("\(item.service) \(item.label) \(item.proxy.server):\(item.proxy.port) 没有进程监听")
                verdict = .duan
            }
        }
    }
    let summary: String
    switch verdict {
    case .duan:
        summary = s.gatewayProbeOK == false ? "网关没有响应，或本地代理端口是空的" : "本地该听的端口没有进程"
    case .partial:
        summary = "本地下一跳只是推断，没有探测"
    case .unknown:
        summary = "本地连通证据不足"
    case .tong:
        summary = s.gatewayProbeOK == true ? "网关可达，该听的本地端口也在听" : "本地代理端口正常"
    }
    return hop(7, verdict, summary, evidence, inferred: inferred, gap: gap)
}

private struct Hop8Box {
    var result: HopResult
    var assessment: Hop8Assessment
}

private func hop8(_ s: LocalSignals) -> Hop8Box {
    if s.scope == .local {
        let result = hop(
            8,
            .unknown,
            "局部检测没有做第 8 环",
            [
                "范围：局部检测",
                "没有向 baidu、境外 443，或经隧道的同一目标发起探测",
                "ping 1.1.1.1 也不会在局部检测里被当成在线证明",
            ],
            gap: "信息缺口：局部检测只做到本机和局域网。要区分 Wi-Fi 上游、境外 VPN 路径和探测本身失败，需要全局检测。"
        )
        return Hop8Box(result: result, assessment: .notRun)
    }

    var evidence = [
        "网关：\(labeled(s.gatewayProbeOK, s.gatewayProbeDetail))",
        "境内直连 HTTPS（绕过代理，例如 baidu）：\(labeled(s.domesticDirectOK, s.domesticDirectDetail))",
        "境外直连 443：\(labeled(s.foreignDirectOK, s.foreignDirectDetail))",
        s.foreignViaTunnelAttempted
            ? "同一境外目标经本地代理或隧道：\(labeled(s.foreignViaTunnelOK, s.foreignViaTunnelDetail))"
            : "没有做经隧道的对照探测",
        "ping 1.1.1.1：\(labeled(s.icmp1111OK, s.icmp1111Detail))。成功不能证明这台 Mac 在线，失败也只说明这一次探测失败。",
    ]
    if s.leftover {
        evidence.append("本机残留信号：\(leftoverFootnote(s))")
    }

    let linkAssociated = (s.wifi.associated && !s.wifi.powerOff) || s.ethernetUp
    if linkAssociated && s.gatewayProbeOK == false {
        return Hop8Box(
            result: hop(8, .duan, "已经连上 Wi-Fi 或以太网，但网关不可达。这是本地链路或当前 Wi-Fi 上游没网，不是代理地址写错。", evidence),
            assessment: .localUpstreamDown
        )
    }
    if s.gatewayProbeOK == true && s.domesticDirectOK == false {
        var extra = evidence
        if s.icmp1111OK == true {
            extra.append("ping 1.1.1.1 虽然成功，校园网或中间设备可以让它说谎，所以不把它当成在线。")
        }
        return Hop8Box(
            result: hop(8, .duan, "网关是通的，但绕过代理的境内直连仍然失败。更像当前链路或 Wi-Fi 上游没网，不是代理填错。", extra),
            assessment: .localUpstreamDown
        )
    }
    if s.leftover && s.domesticDirectOK != false {
        return Hop8Box(
            result: hop(8, .duan, leftoverSummary(s), evidence),
            assessment: .leftover
        )
    }
    if s.gatewayProbeOK == nil && s.domesticDirectOK == false {
        return Hop8Box(
            result: hop(
                8,
                .duan,
                "境内直连失败，但没有网关探测。倾向是本地链路或上游，不是代理笔误；证据还不完整。",
                evidence,
                inferred: true,
                gap: "缺少网关是否可达的测量。"
            ),
            assessment: .localUpstreamDown
        )
    }

    let tunnel = hasTunnelPath(s)
    let healthy = localClientHealthy(s)
    if s.domesticDirectOK == true && tunnel && healthy && s.foreignViaTunnelAttempted && s.foreignViaTunnelOK == false {
        return Hop8Box(
            result: hop(
                8,
                .duan,
                "境内直连是通的，本地客户端和端口也在。走隧道或代理访问境外目标失败，更像 VPN、节点或境外一侧不通。",
                evidence
            ),
            assessment: .foreignPathDown
        )
    }
    if s.domesticDirectOK == true && tunnel && healthy && !s.foreignViaTunnelAttempted {
        return Hop8Box(
            result: hop(
                8,
                .unknown,
                "境内直连可用，也发现了隧道，但没有经隧道的对照探测。",
                evidence,
                gap: "信息缺口：缺了「同一境外目标走隧道」这一笔，不能判断节点。"
            ),
            assessment: .informationGap
        )
    }
    if s.domesticDirectOK == true && s.foreignViaTunnelOK != false && (s.foreignDirectOK == false || s.icmp1111OK == false) && (!tunnel || !healthy) {
        let failed = failedProbeNames(s).joined(separator: "、")
        return Hop8Box(
            result: hop(
                8,
                .partial,
                "境内直连可用。失败的只是这些探测：\(failed)。不能据此判断整台 Mac 离线。",
                evidence
            ),
            assessment: .probesFailedOnly
        )
    }
    if s.domesticDirectOK == true && (s.foreignDirectOK == true || s.foreignViaTunnelOK == true) && s.foreignViaTunnelOK != false {
        return Hop8Box(
            result: hop(8, .tong, "对照探测里，该通的目标是通的", evidence),
            assessment: .reachable
        )
    }
    if s.icmp1111OK == false && s.domesticDirectOK == nil && s.gatewayProbeOK == nil && s.foreignDirectOK == nil && s.foreignViaTunnelOK == nil {
        return Hop8Box(
            result: hop(
                8,
                .unknown,
                "只有 ping 1.1.1.1 失败。这只说明该探测失败，不能判断没网。",
                evidence,
                gap: "信息缺口：没有境内直连、网关和境外 443 的对照。"
            ),
            assessment: .probesFailedOnly
        )
    }
    return Hop8Box(
        result: hop(8, .unknown, "外部探测的证据不够，不下结论", evidence, gap: "信息缺口：第 8 环需要网关、境内直连、境外直连和经隧道对照里的有效结果。"),
        assessment: .informationGap
    )
}

private func labeled(_ value: Bool?, _ detail: String) -> String {
    let head = describe(value)
    let tail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    return tail.isEmpty ? head : "\(head)。\(tail)"
}

private func describe(_ value: Bool?) -> String {
    switch value {
    case true: return "成功"
    case false: return "失败"
    case nil: return "没有测"
    }
}

private func failedProbeNames(_ s: LocalSignals) -> [String] {
    var names: [String] = []
    if s.foreignDirectOK == false { names.append("境外直连 443") }
    if s.icmp1111OK == false { names.append("ping 1.1.1.1") }
    if s.foreignViaTunnelOK == false { names.append("经隧道的境外目标") }
    if names.isEmpty { names.append("标出的外部探测") }
    return names
}

private func leftoverSummary(_ s: LocalSignals) -> String {
    if !s.deadLoopbackProxies.isEmpty {
        let first = s.deadLoopbackProxies[0]
        return "系统代理仍指向 \(first.proxy.server):\(first.proxy.port)，但没有进程监听。这是本地残留，不是上游断网。"
    }
    if s.dnsHijackDead {
        return "DNS 仍指向 127.0.0.1，但没有进程监听 53。这是本地残留。"
    }
    if s.staleUtun {
        return "utun 路由还在，隧道进程已经不在。这是本地残留，不是代理少写了一行。"
    }
    return "本地代理或隧道配置残留。"
}

private func leftoverFootnote(_ s: LocalSignals) -> String {
    var parts: [String] = []
    if !s.deadLoopbackProxies.isEmpty {
        let text = s.deadLoopbackProxies.map { "\($0.service) \($0.label) \($0.proxy.server):\($0.proxy.port)" }.joined(separator: "、")
        parts.append("系统代理指向 \(text)，端口没有监听")
    }
    if s.dnsHijackDead {
        parts.append("DNS 指向 127.0.0.1 且 53 端口没有监听")
    }
    if s.staleUtun {
        parts.append("utun 路由还在，但 Clash / Surge / WireGuard / 系统 VPN 都不在")
    }
    return parts.isEmpty ? "存在残留配置" : parts.joined(separator: "；")
}

private func hasTunnelPath(_ s: LocalSignals) -> Bool {
    if !s.enabledProxies.isEmpty { return true }
    if s.vpn.contains(where: \.connected) { return true }
    if !s.utunDefaults.isEmpty && s.tunnelExplained { return true }
    if s.clash?.tun == true || s.clash?.mode == "global" { return true }
    if !s.clients.isEmpty { return true }
    return false
}

private func localClientHealthy(_ s: LocalSignals) -> Bool {
    if !s.deadLoopbackProxies.isEmpty { return false }
    if s.dnsHijackDead { return false }
    if s.staleUtun { return false }
    return true
}

private func isCampus(_ s: LocalSignals) -> Bool {
    s.campusSSID || s.wpadOn
}

private func campusRelevant(_ s: LocalSignals) -> Bool {
    s.wpadOn || hasLiveSystemProxy(s) || s.vpn.contains(where: \.connected) || !s.utunDefaults.isEmpty || !s.clients.isEmpty
}

private func isTunGlobal(_ s: LocalSignals) -> Bool {
    if s.clash?.mode == "global" { return true }
    if s.clash?.tun == true { return true }
    if !s.utunDefaults.isEmpty && s.tunnelExplained { return true }
    return false
}

private func isRuleSplit(_ s: LocalSignals) -> Bool {
    if isTunGlobal(s) { return false }
    if s.clash?.mode == "rule" { return true }
    let ruleClient = s.clients.contains { $0.brand == .surge || $0.brand == .singBox }
    if ruleClient && s.utunDefaults.isEmpty && (hasLiveSystemProxy(s) || !s.listeners.isEmpty) {
        return true
    }
    return false
}

private func hasLiveSystemProxy(_ s: LocalSignals) -> Bool {
    s.enabledProxies.contains { proxy in
        if isLoopback(proxy.proxy.server) {
            return isListening(proxy.proxy.server, proxy.proxy.port, s.listeners)
        }
        return !proxy.proxy.server.isEmpty && proxy.proxy.port > 0
    }
}

private func isSplitTunnel(_ s: LocalSignals) -> Bool {
    if !s.utunDefaults.isEmpty { return false }
    if hasLiveSystemProxy(s) { return false }
    if s.vpn.contains(where: \.connected) { return true }
    return s.clients.contains {
        $0.brand == .tailscale || $0.brand == .wireguard || $0.brand == .anyconnect || $0.brand == .atrust || $0.brand == .openvpn
    }
}
