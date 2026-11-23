import Foundation

enum WiFiDraft {
    case associated(ssid: String, rssi: Int?)
    case off
    case disconnected
    case absent
}

struct ServiceDraft {
    var name: String
    var disabled: Bool = false
    var dhcp: Bool = true
    var ip: String? = "192.168.1.23"
    var router: String? = "192.168.1.1"
    var web: (enabled: Bool, host: String, port: Int)?
    var https: (enabled: Bool, host: String, port: Int)?
    var socks: (enabled: Bool, host: String, port: Int)?
    var pacURL: String?
    var wpad: Bool = false
    /// nil means "there aren't any DNS servers set".
    var dns: [String]? = nil

    static func wifi(ip: String? = "192.168.1.23", router: String? = "192.168.1.1") -> ServiceDraft {
        ServiceDraft(name: "Wi-Fi", ip: ip, router: router)
    }

    static func ethernet(ip: String? = nil, router: String? = nil, disabled: Bool = true) -> ServiceDraft {
        ServiceDraft(name: "Ethernet", disabled: disabled, ip: ip, router: router)
    }
}

struct ListenerDraft {
    var process: String
    var host: String
    var port: Int
    var udp: Bool = false
}

struct RouteDraft {
    var gateway: String
    var interfaceName: String
}

struct VPNDraft {
    var connected: Bool
    var name: String
    var kind: String
}

struct Draft {
    var services: [ServiceDraft] = [.wifi(), .ethernet()]
    var wifi: WiFiDraft = .associated(ssid: "MizLab", rssi: -58)
    var routes: [RouteDraft] = [RouteDraft(gateway: "192.168.1.1", interfaceName: "en0")]
    var routeMissing: Bool = false
    var listeners: [ListenerDraft] = []
    var processes: [String] = []
    var vpns: [VPNDraft] = []
    var scutilDNS: [String] = ["192.168.1.1"]
    var clashJSON: String?
    var clashBase: String?
    var scope: DetectScope = .local
    var gatewayOK: Bool? = true
    var domesticOK: Bool? = nil
    var foreignDirectOK: Bool? = nil
    var foreignViaOK: Bool? = nil
    var viaAttempted: Bool = false
    var icmpOK: Bool? = nil
    var tunInet: String?
    var includeWiFiHardware: Bool = true
    var includeEthernetHardware: Bool = true
    var notes: [String] = []

    func make() -> ProbeBundle {
        var bundle = ProbeBundle()
        bundle.hardwarePorts = hardwareText()
        bundle.networkServices = serviceListText()
        for service in services {
            bundle.serviceInfo[service.name] = infoText(service)
            bundle.webProxy[service.name] = proxyText(service.web)
            bundle.secureWebProxy[service.name] = proxyText(service.https)
            bundle.socksProxy[service.name] = proxyText(service.socks)
            bundle.autoProxyURL[service.name] = pacText(service.pacURL)
            bundle.autoDiscovery[service.name] = service.wpad ? "Auto Proxy Discovery: On\n" : "Auto Proxy Discovery: Off\n"
            bundle.dnsServers[service.name] = dnsText(service)
        }
        bundle.scutilProxy = scutilProxyText()
        bundle.scutilDNS = scutilDNSText()
        bundle.scutilNC = scutilNCText()
        if routeMissing {
            bundle.routeGetDefault = "route: bad address\nget route: not in table\n"
            bundle.netstatRN = "Routing tables\n\nInternet:\nDestination        Gateway            Flags           Netif Expire\n127.0.0.1          127.0.0.1          UH                lo0\n"
        } else if let first = routes.first {
            bundle.routeGetDefault = """
               route to: default
            destination: default
                   mask: default
                gateway: \(first.gateway)
              interface: \(first.interfaceName)
                  flags: <UP,GATEWAY,DONE,STATIC,PRCLONING>

            """
            var table = "Routing tables\n\nInternet:\nDestination        Gateway            Flags           Netif Expire\n"
            for route in routes {
                table += "default            \(route.gateway)        UGSc              \(route.interfaceName)\n"
            }
            table += "127.0.0.1          127.0.0.1          UH                lo0\n"
            bundle.netstatRN = table
        }
        bundle.ifconfig = ifconfigText()
        bundle.lsof = lsofText()
        bundle.processList = processes.joined(separator: "\n")
        bundle.wifiInfo = wifiText()
        bundle.clashAPI = clashJSON
        bundle.clashAPIBase = clashBase
        bundle.scope = scope
        bundle.gatewayProbeOK = gatewayOK
        bundle.gatewayProbeDetail = gatewayOK == nil ? "" : (gatewayOK == true ? "ping 网关 1 次成功" : "ping 网关 1 次失败")
        bundle.domesticDirectOK = domesticOK
        bundle.domesticDirectDetail = domesticOK == nil ? "" : "curl --noproxy * https://www.baidu.com"
        bundle.foreignDirectOK = foreignDirectOK
        bundle.foreignDirectDetail = foreignDirectOK == nil ? "" : "nc 到 1.1.1.1:443，绑定物理网卡"
        bundle.foreignViaTunnelOK = foreignViaOK
        bundle.foreignViaTunnelDetail = foreignViaOK == nil ? "" : "同一境外目标经本地代理或默认隧道"
        bundle.foreignViaTunnelAttempted = viaAttempted
        bundle.icmp1111OK = icmpOK
        bundle.icmp1111Detail = icmpOK == nil ? "" : "ping -c 1 1.1.1.1"
        bundle.notes = notes
        return bundle
    }

    private func hardwareText() -> String {
        var text = ""
        if includeWiFiHardware {
            text += "Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: 14:7d:da:11:22:33\n\n"
        }
        if includeEthernetHardware {
            text += "Hardware Port: Ethernet\nDevice: en7\nEthernet Address: 14:7d:da:44:55:66\n\n"
        }
        return text
    }

    private func serviceListText() -> String {
        var lines = ["An asterisk (*) denotes that a network service is disabled."]
        for service in services {
            lines.append(service.disabled ? "*\(service.name)" : service.name)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func infoText(_ service: ServiceDraft) -> String {
        let method = service.dhcp ? "DHCP Configuration" : "Manual Configuration"
        let ip = service.ip ?? "none"
        let router = service.router ?? "none"
        return """
        \(method)
        IP address: \(ip)
        Subnet mask: 255.255.255.0
        Router: \(router)
        Client ID:
        IPv6: Automatic
        IPv6 IP address: none
        IPv6 Router: none

        """
    }

    private func proxyText(_ value: (enabled: Bool, host: String, port: Int)?) -> String {
        let enabled = value?.enabled == true
        return """
        Enabled: \(enabled ? "Yes" : "No")
        Server: \(value?.host ?? "")
        Port: \(value?.port ?? 0)
        Authenticated Proxy Enabled: 0

        """
    }

    private func pacText(_ url: String?) -> String {
        if let url {
            return "URL: \(url)\nEnabled: Yes\n"
        }
        return "URL: (null)\nEnabled: No\n"
    }

    private func dnsText(_ service: ServiceDraft) -> String {
        guard let dns = service.dns, !dns.isEmpty else {
            return "There aren't any DNS Servers set on \(service.name).\n"
        }
        return dns.joined(separator: "\n") + "\n"
    }

    private func scutilProxyText() -> String {
        let https = services.first { $0.https?.enabled == true }?.https
        let http = services.first { $0.web?.enabled == true }?.web
        let socks = services.first { $0.socks?.enabled == true }?.socks
        let pac = services.contains { $0.pacURL != nil }
        let wpad = services.contains { $0.wpad }
        return """
        <dictionary> {
          HTTPEnable : \(http?.enabled == true ? 1 : 0)
          HTTPPort : \(http?.port ?? 0)
          HTTPProxy : \(http?.host ?? "")
          HTTPSEnable : \(https?.enabled == true ? 1 : 0)
          HTTPSPort : \(https?.port ?? 0)
          HTTPSProxy : \(https?.host ?? "")
          SOCKSEnable : \(socks?.enabled == true ? 1 : 0)
          SOCKSPort : \(socks?.port ?? 0)
          SOCKSProxy : \(socks?.host ?? "")
          ProxyAutoConfigEnable : \(pac ? 1 : 0)
          ProxyAutoDiscoveryEnable : \(wpad ? 1 : 0)
        }

        """
    }

    private func scutilDNSText() -> String {
        if scutilDNS.isEmpty { return "DNS configuration\n\n" }
        var text = "DNS configuration\n\nresolver #1\n"
        for (index, server) in scutilDNS.enumerated() {
            text += "  nameserver[\(index)] : \(server)\n"
        }
        text += "  if_index : 14 (en0)\n"
        return text
    }

    private func scutilNCText() -> String {
        var text = "Available network connection services in the current set (*=enabled):\n"
        if vpns.isEmpty { return text }
        for vpn in vpns {
            let state = vpn.connected ? "Connected" : "Disconnected"
            text += "* (\(state))       8F2A1C00-0000-0000-0000-000000000001 \"\(vpn.name)\" [VPN:\(vpn.kind)]\n"
        }
        return text
    }

    private func ifconfigText() -> String {
        var text = ""
        for service in services {
            guard let ip = service.ip, usableIPv4(ip) || isLinkLocal(ip) else { continue }
            let device = service.name == "Ethernet" ? "en7" : "en0"
            text += "\(device): flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n"
            text += "\tinet \(ip) netmask 0xffffff00 broadcast 192.168.1.255\n"
            text += "\tstatus: active\n"
        }
        if let tunInet {
            text += "utun3: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 9000\n"
            text += "\tinet \(tunInet) --> \(tunInet) netmask 0xffffffff\n"
        } else if routes.contains(where: { $0.interfaceName.hasPrefix("utun") }) {
            text += "utun3: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 9000\n"
            text += "\tinet 198.18.0.1 --> 198.18.0.1 netmask 0xffffffff\n"
        }
        return text
    }

    private func lsofText() -> String {
        var lines = ["COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"]
        for listener in listeners {
            if listener.udp {
                lines.append("\(listener.process) 100 user 10u IPv4 0x1 0t0 UDP \(listener.host):\(listener.port)")
            } else {
                lines.append("\(listener.process) 100 user 8u IPv4 0x1 0t0 TCP \(listener.host):\(listener.port) (LISTEN)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func wifiText() -> String {
        switch wifi {
        case .associated(let ssid, let rssi):
            let rssiLine = rssi.map { "RSSI: \($0)\n" } ?? ""
            return "Current Wi-Fi Network: \(ssid)\n\(rssiLine)interface: en0\npower: on\n"
        case .off:
            return "Wi-Fi is off\npower: off\ninterface: en0\n"
        case .disconnected:
            return "You are not associated with an AirPort network.\npower: on\ninterface: en0\n"
        case .absent:
            return ""
        }
    }
}

public enum DemoLibrary {
    public static func named(_ name: String) -> ProbeBundle? {
        switch name {
        case "clean": return cleanWiFi()
        case "proxy": return proxyOn()
        case "leftover": return leftoverProxy()
        case "upstream": return upstreamDomestic()
        case "foreign": return foreignPath()
        case "wifi-off": return wifiOff()
        case "tun": return tunGlobal()
        case "rule": return ruleSplit()
        default: return nil
        }
    }

    public static var demoNames: [String] {
        ["clean", "proxy", "leftover", "upstream", "foreign", "wifi-off", "tun", "rule"]
    }

    public static func allBundles() -> [ProbeBundle] {
        [
            cleanWiFi(), ethernetClean(), proxyOn(), proxyWithoutAPI(), leftoverProxy(), leftoverDNS(),
            noDefaultRoute(), badDNS(), tunGlobal(), ruleSplit(), wifiOff(), probesFailedOnly(),
            pingIsNotOnline(), localScopeIgnoresFilledProbes(), upstreamGateway(), upstreamDomestic(),
            foreignPath(), hop8Leftover(), staleUtun(), hop8Gap(), campusMixed(), pac(), socksOnly(),
            disabledServiceProxy(), linkLocal(), anyConnect(), tailscale(), wireGuard(), surge(),
            singBox(), v2ray(), weakSignal(), twoDefaults(), clashAndSurge(), atrust(), remoteProxy(),
            twoServices(), clashGlobalHealthy(), empty(),
        ]
    }

    public static func cleanWiFi(scope: DetectScope = .local) -> ProbeBundle {
        var draft = Draft()
        draft.scope = scope
        return draft.make()
    }

    public static func ethernetClean() -> ProbeBundle {
        var draft = Draft()
        draft.services = [.ethernet(ip: "10.8.0.20", router: "10.8.0.1", disabled: false)]
        draft.wifi = .off
        draft.routes = [RouteDraft(gateway: "10.8.0.1", interfaceName: "en7")]
        draft.scutilDNS = ["10.8.0.1"]
        return draft.make()
    }

    public static func proxyOn() -> ProbeBundle {
        clashRuleDraft().make()
    }

    public static func proxyWithoutAPI() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].web = (true, "127.0.0.1", 7890)
        draft.services[0].https = (true, "127.0.0.1", 7890)
        draft.listeners = [ListenerDraft(process: "verge-mihomo", host: "127.0.0.1", port: 7890)]
        draft.processes = ["/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo"]
        return draft.make()
    }

    public static func leftoverProxy() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].web = (true, "127.0.0.1", 7890)
        draft.services[0].https = (true, "127.0.0.1", 7890)
        draft.scope = .global
        draft.domesticOK = true
        draft.gatewayOK = true
        return draft.make()
    }

    public static func leftoverDNS() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].dns = ["127.0.0.1"]
        draft.scutilDNS = ["127.0.0.1"]
        return draft.make()
    }

    public static func noDefaultRoute() -> ProbeBundle {
        var draft = Draft()
        draft.routeMissing = true
        draft.routes = []
        draft.gatewayOK = nil
        return draft.make()
    }

    public static func badDNS() -> ProbeBundle {
        var draft = Draft()
        draft.scutilDNS = []
        return draft.make()
    }

    public static func tunGlobal() -> ProbeBundle {
        var draft = clashRuleDraft()
        draft.clashJSON = #"{"mode":"rule","mixed-port":7890,"tun":{"enable":true}}"#
        draft.routes = [RouteDraft(gateway: "198.18.0.1", interfaceName: "utun3")]
        draft.tunInet = "198.18.0.1"
        return draft.make()
    }

    public static func ruleSplit() -> ProbeBundle {
        clashRuleDraft().make()
    }

    public static func wifiOff() -> ProbeBundle {
        var draft = Draft()
        draft.wifi = .off
        draft.services[0].ip = nil
        draft.services[0].router = nil
        draft.routeMissing = true
        draft.routes = []
        draft.gatewayOK = nil
        draft.scutilDNS = []
        return draft.make()
    }

    public static func probesFailedOnly() -> ProbeBundle {
        var draft = Draft()
        draft.scope = .global
        draft.domesticOK = true
        draft.foreignDirectOK = false
        draft.icmpOK = false
        draft.gatewayOK = true
        return draft.make()
    }

    public static func pingIsNotOnline() -> ProbeBundle {
        var draft = Draft()
        draft.scope = .global
        draft.gatewayOK = true
        draft.domesticOK = false
        draft.icmpOK = true
        return draft.make()
    }

    public static func localScopeIgnoresFilledProbes() -> ProbeBundle {
        var draft = Draft()
        draft.scope = .local
        draft.domesticOK = false
        draft.foreignDirectOK = false
        draft.icmpOK = false
        draft.gatewayOK = false
        return draft.make()
    }

    public static func upstreamGateway() -> ProbeBundle {
        var draft = Draft()
        draft.scope = .global
        draft.gatewayOK = false
        draft.domesticOK = false
        return draft.make()
    }

    public static func upstreamDomestic() -> ProbeBundle {
        var draft = Draft()
        draft.scope = .global
        draft.gatewayOK = true
        draft.domesticOK = false
        draft.foreignDirectOK = false
        return draft.make()
    }

    public static func foreignPath() -> ProbeBundle {
        var draft = clashRuleDraft()
        draft.scope = .global
        draft.gatewayOK = true
        draft.domesticOK = true
        draft.foreignDirectOK = false
        draft.foreignViaOK = false
        draft.viaAttempted = true
        return draft.make()
    }

    public static func hop8Leftover() -> ProbeBundle {
        leftoverProxy()
    }

    public static func staleUtun() -> ProbeBundle {
        var draft = Draft()
        draft.scope = .global
        draft.routes = [RouteDraft(gateway: "198.18.0.1", interfaceName: "utun3")]
        draft.tunInet = "198.18.0.1"
        draft.gatewayOK = true
        draft.domesticOK = true
        draft.processes = []
        return draft.make()
    }

    public static func hop8Gap() -> ProbeBundle {
        var draft = Draft()
        draft.scope = .global
        draft.gatewayOK = nil
        draft.domesticOK = nil
        draft.foreignDirectOK = nil
        return draft.make()
    }

    public static func campusMixed() -> ProbeBundle {
        var draft = clashRuleDraft()
        draft.wifi = .associated(ssid: "Campus-Miz", rssi: -62)
        draft.services[0].wpad = true
        return draft.make()
    }

    public static func pac() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].pacURL = "http://127.0.0.1:6152/proxy.pac"
        draft.services[0].https = (true, "127.0.0.1", 6152)
        draft.listeners = [ListenerDraft(process: "Surge", host: "127.0.0.1", port: 6152)]
        draft.processes = ["/Applications/Surge.app/Contents/MacOS/Surge"]
        return draft.make()
    }

    public static func socksOnly() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].socks = (true, "127.0.0.1", 7891)
        draft.listeners = [ListenerDraft(process: "verge-mihomo", host: "127.0.0.1", port: 7891)]
        draft.processes = ["/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo"]
        draft.clashJSON = #"{"mode":"rule","mixed-port":7890}"#
        draft.clashBase = "http://127.0.0.1:9090"
        return draft.make()
    }

    public static func disabledServiceProxy() -> ProbeBundle {
        var draft = Draft()
        draft.services[1].web = (true, "127.0.0.1", 7890)
        draft.services[1].https = (true, "127.0.0.1", 7890)
        return draft.make()
    }

    public static func linkLocal() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].ip = "169.254.12.4"
        draft.services[0].router = nil
        draft.routeMissing = true
        draft.routes = []
        draft.gatewayOK = false
        return draft.make()
    }

    public static func anyConnect() -> ProbeBundle {
        var draft = Draft()
        draft.vpns = [VPNDraft(connected: true, name: "Cisco AnyConnect", kind: "com.cisco.anyconnect.connect")]
        draft.processes = ["/opt/cisco/anyconnect/bin/vpnagentd"]
        return draft.make()
    }

    public static func tailscale() -> ProbeBundle {
        var draft = Draft()
        draft.processes = ["/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
        draft.tunInet = "100.64.0.8"
        return draft.make()
    }

    public static func wireGuard() -> ProbeBundle {
        var draft = Draft()
        draft.processes = ["/Applications/WireGuard.app/Contents/MacOS/WireGuard"]
        draft.routes = [RouteDraft(gateway: "10.7.0.1", interfaceName: "utun4")]
        return draft.make()
    }

    public static func surge() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].https = (true, "127.0.0.1", 6152)
        draft.listeners = [ListenerDraft(process: "Surge", host: "127.0.0.1", port: 6152)]
        draft.processes = ["/Applications/Surge.app/Contents/MacOS/Surge"]
        return draft.make()
    }

    public static func singBox() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].socks = (true, "127.0.0.1", 2080)
        draft.listeners = [ListenerDraft(process: "sing-box", host: "127.0.0.1", port: 2080)]
        draft.processes = ["/usr/local/bin/sing-box run"]
        return draft.make()
    }

    public static func v2ray() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].socks = (true, "127.0.0.1", 1080)
        draft.listeners = [ListenerDraft(process: "xray", host: "127.0.0.1", port: 1080)]
        draft.processes = ["/usr/local/bin/xray run"]
        return draft.make()
    }

    public static func weakSignal() -> ProbeBundle {
        var draft = Draft()
        draft.wifi = .associated(ssid: "MizLab", rssi: -85)
        return draft.make()
    }

    public static func twoDefaults() -> ProbeBundle {
        var draft = clashRuleDraft()
        draft.routes = [
            RouteDraft(gateway: "192.168.1.1", interfaceName: "en0"),
            RouteDraft(gateway: "198.18.0.1", interfaceName: "utun3"),
        ]
        draft.tunInet = "198.18.0.1"
        return draft.make()
    }

    public static func clashAndSurge() -> ProbeBundle {
        var draft = clashRuleDraft()
        draft.processes.append("/Applications/Surge.app/Contents/MacOS/Surge")
        return draft.make()
    }

    public static func atrust() -> ProbeBundle {
        var draft = Draft()
        draft.vpns = [VPNDraft(connected: true, name: "aTrust", kind: "com.sangfor.atrust")]
        draft.processes = ["/Applications/aTrust.app/Contents/MacOS/aTrust"]
        return draft.make()
    }

    public static func remoteProxy() -> ProbeBundle {
        var draft = Draft()
        draft.services[0].https = (true, "10.1.2.3", 3128)
        return draft.make()
    }

    public static func twoServices() -> ProbeBundle {
        let ethernet = ServiceDraft.ethernet(ip: "10.8.0.20", router: "10.8.0.1", disabled: false)
        var draft = Draft()
        draft.services = [.wifi(), ethernet]
        return draft.make()
    }

    public static func clashGlobalHealthy() -> ProbeBundle {
        var draft = clashRuleDraft()
        draft.clashJSON = #"{"mode":"global","mixed-port":7890,"tun":{"enable":false}}"#
        draft.scope = .global
        draft.domesticOK = true
        draft.foreignDirectOK = false
        draft.foreignViaOK = true
        draft.viaAttempted = true
        draft.gatewayOK = true
        return draft.make()
    }

    public static func clashGlobalBroken() -> ProbeBundle {
        var draft = clashRuleDraft()
        draft.clashJSON = #"{"mode":"global","mixed-port":7890,"tun":{"enable":false}}"#
        draft.scope = .global
        draft.gatewayOK = true
        draft.domesticOK = true
        draft.foreignViaOK = false
        draft.viaAttempted = true
        return draft.make()
    }

    public static func empty() -> ProbeBundle {
        ProbeBundle()
    }

    private static func clashRuleDraft() -> Draft {
        var draft = Draft()
        draft.services[0].web = (true, "127.0.0.1", 7890)
        draft.services[0].https = (true, "127.0.0.1", 7890)
        draft.listeners = [
            ListenerDraft(process: "verge-mihomo", host: "127.0.0.1", port: 7890),
            ListenerDraft(process: "verge-mihomo", host: "127.0.0.1", port: 9090),
        ]
        draft.processes = ["/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo"]
        draft.clashJSON = #"{"mode":"rule","mixed-port":7890,"tun":{"enable":false}}"#
        draft.clashBase = "http://127.0.0.1:9090"
        return draft
    }
}
