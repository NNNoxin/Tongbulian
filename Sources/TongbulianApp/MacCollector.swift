import Foundation
import CoreWLAN
import CoreLocation

/// Reads the Mac. It never changes proxy, DNS, routes, or VPN.
enum MacCollector {
    static func collect(scope: DetectScope) -> ProbeBundle {
        var bundle = ProbeBundle()
        bundle.scope = scope
        bundle.hardwarePorts = shell(["/usr/sbin/networksetup", "-listallhardwareports"])
        bundle.networkServices = shell(["/usr/sbin/networksetup", "-listallnetworkservices"])
        let names = networkServiceNames(bundle.networkServices)
        for name in names {
            bundle.serviceInfo[name] = shell(["/usr/sbin/networksetup", "-getinfo", name])
            bundle.webProxy[name] = shell(["/usr/sbin/networksetup", "-getwebproxy", name])
            bundle.secureWebProxy[name] = shell(["/usr/sbin/networksetup", "-getsecurewebproxy", name])
            bundle.socksProxy[name] = shell(["/usr/sbin/networksetup", "-getsocksfirewallproxy", name])
            bundle.autoProxyURL[name] = shell(["/usr/sbin/networksetup", "-getautoproxyurl", name])
            bundle.autoDiscovery[name] = shell(["/usr/sbin/networksetup", "-getproxyautodiscovery", name])
            bundle.dnsServers[name] = shell(["/usr/sbin/networksetup", "-getdnsservers", name])
        }
        bundle.scutilProxy = shell(["/usr/sbin/scutil", "--proxy"])
        bundle.scutilDNS = shell(["/usr/sbin/scutil", "--dns"])
        bundle.scutilNC = shell(["/usr/sbin/scutil", "--nc", "list"])
        bundle.routeGetDefault = shell(["/sbin/route", "-n", "get", "default"])
        bundle.netstatRN = shell(["/usr/sbin/netstat", "-rn", "-f", "inet"])
        bundle.ifconfig = shell(["/sbin/ifconfig"])
        bundle.lsof = shell(["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP"], timeout: 8)
        bundle.processList = shell(["/bin/ps", "-ax", "-o", "pid=,command="], timeout: 6)
        bundle.wifiInfo = wifiInfo()
        if !ssidLikelyAvailable() {
            bundle.notes.append("没有定位权限时，macOS 不给出 SSID。通不连只拿它来给网络起名字，不记录坐标。")
        }
        attachClash(&bundle)
        probeGateway(&bundle)
        if scope == .global {
            probeTargets(&bundle)
        }
        return bundle
    }

    private static func wifiInfo() -> String {
        let client = CWWiFiClient.shared()
        guard let iface = client.interface() else {
            return shell(["/usr/sbin/networksetup", "-getairportnetwork", "en0"])
        }
        let name = iface.interfaceName ?? "en0"
        if iface.powerOn() == false {
            return "Wi-Fi is off\npower: off\ninterface: \(name)\n"
        }
        let rssi = iface.rssiValue()
        let rssiLine = rssi == 0 ? "" : "RSSI: \(rssi)\n"
        if let ssid = iface.ssid, !ssid.isEmpty {
            return "Current Wi-Fi Network: \(ssid)\n\(rssiLine)interface: \(name)\npower: on\n"
        }
        let airport = shell(["/usr/sbin/networksetup", "-getairportnetwork", name])
        return airport + "\n" + rssiLine + "interface: \(name)\npower: on\n"
    }

    private static func ssidLikelyAvailable() -> Bool {
        // 3 = authorized / authorizedAlways, 4 = authorizedWhenInUse. Avoid the deprecated case name.
        let raw = CLLocationManager.authorizationStatus().rawValue
        return raw == 3 || raw == 4
    }

    private static func attachClash(_ bundle: inout ProbeBundle) {
        guard bundle.lsof.contains("127.0.0.1:9090") || bundle.lsof.contains("localhost:9090") else { return }
        guard let url = URL(string: "http://127.0.0.1:9090/configs") else { return }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"
        let result = syncData(request)
        if result.status == 200, let body = result.body {
            bundle.clashAPI = body
            bundle.clashAPIBase = "http://127.0.0.1:9090"
        } else {
            bundle.notes.append("本机 9090 在听，但 Clash API 没有返回配置。通不连不会去读配置文件，也不会猜密钥。")
        }
    }

    private static func probeGateway(_ bundle: inout ProbeBundle) {
        guard let gateway = routeField(bundle.routeGetDefault, "gateway:") else {
            bundle.gatewayProbeOK = nil
            bundle.gatewayProbeDetail = "路由里没有网关，跳过局域网探测"
            return
        }
        let result = shellStatus(["/sbin/ping", "-c", "1", "-W", "1000", gateway], timeout: 3)
        bundle.gatewayProbeOK = result.code == 0
        bundle.gatewayProbeDetail = result.code == 0 ? "ping \(gateway) 成功" : "ping \(gateway) 失败"
    }

    private static func probeTargets(_ bundle: inout ProbeBundle) {
        let iface = routeField(bundle.routeGetDefault, "interface:") ?? "en0"
        let source = ipv4(bundle.ifconfig, interface: iface)
        var direct: [String] = ["/usr/bin/nc", "-z", "-G", "5"]
        if let source {
            direct.append(contentsOf: ["-s", source])
        }
        direct.append(contentsOf: ["1.1.1.1", "443"])
        let foreign = shellStatus(direct, timeout: 8)
        bundle.foreignDirectOK = foreign.code == 0
        bundle.foreignDirectDetail = "nc 1.1.1.1:443 绑定 \(iface)。这只说明这一次 443，不能单独证明整机在线。"

        let domesticArgs = [
            "/usr/bin/curl", "-4", "--noproxy", "*", "--interface", iface,
            "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "6", "https://www.baidu.com",
        ]
        let domestic = shellStatus(domesticArgs, timeout: 8)
        let code = Int(domestic.text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        bundle.domesticDirectOK = domestic.code == 0 && (200..<400).contains(code)
        bundle.domesticDirectDetail = "curl --noproxy * --interface \(iface) https://www.baidu.com → \(code == 0 ? "无响应" : String(code))"

        if let proxy = loopbackProxy(bundle) {
            let scheme = proxy.socks ? "socks5h" : "http"
            let via = shellStatus([
                "/usr/bin/curl", "-k", "-x", "\(scheme://127.0.0.1:\(proxy.port)",
                "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "8", "https://1.1.1.1/",
            ], timeout: 10)
            let viaCode = Int(via.text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            bundle.foreignViaTunnelAttempted = true
            bundle.foreignViaTunnelOK = via.code == 0 && (200..<400).contains(viaCode)
            bundle.foreignViaTunnelDetail = "同一目标 1.1.1.1 经 \(scheme)://127.0.0.1:\(proxy.port) → \(viaCode == 0 ? "无响应" : String(viaCode))"
        } else if bundle.routeGetDefault.contains("utun") || bundle.netstatRN.contains("utun") {
            let via = shellStatus(["/usr/bin/nc", "-z", "-G", "5", "1.1.1.1", "443"], timeout: 8)
            bundle.foreignViaTunnelAttempted = true
            bundle.foreignViaTunnelOK = via.code == 0
            bundle.foreignViaTunnelDetail = "同一目标 1.1.1.1:443 走当前默认路由（可能是 utun）"
        } else {
            bundle.foreignViaTunnelAttempted = false
            bundle.foreignViaTunnelDetail = "没有本地代理端口，也没有 utun 默认路由，所以没有「经隧道」这一笔"
        }

        let icmp = shellStatus(["/sbin/ping", "-c", "1", "-W", "2000", "1.1.1.1"], timeout: 4)
        bundle.icmp1111OK = icmp.code == 0
        bundle.icmp1111Detail = "单独记录，不作为在线或离线的结论"
    }

    private static func loopbackProxy(_ bundle: ProbeBundle) -> (port: Int, socks: Bool)? {
        for name in bundle.socksProxy.keys.sorted() {
            if let port = enabledLoopbackPort(bundle.socksProxy[name] ?? "") { return (port, true) }
        }
        for name in bundle.secureWebProxy.keys.sorted() {
            if let port = enabledLoopbackPort(bundle.secureWebProxy[name] ?? "") { return (port, false) }
        }
        for name in bundle.webProxy.keys.sorted() {
            if let port = enabledLoopbackPort(bundle.webProxy[name] ?? "") { return (port, false) }
        }
        return nil
    }

    private static func enabledLoopbackPort(_ text: String) -> Int? {
        var enabled = false
        var server = ""
        var port = 0
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Enabled:"), !line.hasPrefix("Authenticated") {
                enabled = line.contains("Yes")
            } else if line.hasPrefix("Server:") {
                server = line.dropFirst("Server:".count).trimmingCharacters(in: .whitespaces).lowercased()
            } else if line.hasPrefix("Port:") {
                port = Int(line.dropFirst("Port:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        guard enabled, server == "127.0.0.1" || server == "localhost", port > 0 else { return nil }
        return port
    }

    private static func routeField(_ text: String, _ key: String) -> String? {
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix(key) {
                let value = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return String(value) }
            }
        }
        return nil
    }

    private static func ipv4(_ ifconfig: String, interface: String) -> String? {
        var current = ""
        for raw in ifconfig.split(separator: "\n") {
            let line = String(raw)
            if !line.hasPrefix("\t"), line.contains("flags=") {
                current = line.split(separator: ":").first.map(String.init) ?? ""
            } else if current == interface, line.trimmingCharacters(in: .whitespaces).hasPrefix("inet ") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count >= 2 { return String(parts[1]) }
            }
        }
        return nil
    }

    private static func syncData(_ request: URLRequest) -> (status: Int, body: String?) {
        let box = ResponseBox()
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            box.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data { box.body = String(data: data, encoding: .utf8) }
            box.semaphore.signal()
        }
        task.resume()
        _ = box.semaphore.wait(timeout: .now() + 3)
        task.cancel()
        return (box.status, box.body)
    }
}

private final class ResponseBox: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var status = 0
    var body: String?
}

private struct ShellResult {
    var text: String
    var code: Int32
}

private func shell(_ argv: [String], timeout: TimeInterval = 8) -> String {
    shellStatus(argv, timeout: timeout).text
}

private func shellStatus(_ argv: [String], timeout: TimeInterval) -> ShellResult {
    guard argv.count >= 1, FileManager.default.isExecutableFile(atPath: argv[0]) else {
        return ShellResult(text: "", code: 127)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: argv[0])
    process.arguments = Array(argv.dropFirst())
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do {
        try process.run()
    } catch {
        return ShellResult(text: "", code: 127)
    }
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
    let killer = DispatchWorkItem {
        if process.isRunning { process.terminate() }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
    process.waitUntilExit()
    killer.cancel()
    group.wait()
    let text = String(data: stdout + stderr, encoding: .utf8) ?? ""
    return ShellResult(text: text, code: process.terminationStatus)
}
