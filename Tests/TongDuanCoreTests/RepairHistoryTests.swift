import XCTest
@testable import TongDuanCore

final class RepairHistoryTests: XCTestCase {
    func testLeftoverPlanPreviewsClear() {
        let bundle = DemoLibrary.leftoverProxy()
        let report = diagnose(bundle)
        let plan = planRepairs(bundle, report: report)
        let item = plan.items.first { $0.id == "clear-proxy-Wi-Fi" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.risk, .safe)
        XCTAssertEqual(item?.initiallyChecked, true)
        XCTAssertTrue(item?.currentValue.contains("127.0.0.1:7890") == true)
        XCTAssertTrue(item?.newValue.contains("关闭") == true)
        XCTAssertFalse(item?.commands.contains(where: {
            if case .setWebProxy = $0 { return true }
            return false
        }) ?? true)
    }

    func testSafeItemsStartCheckedHighRiskUnchecked() {
        let bundle = DemoLibrary.clashGlobalBroken()
        let plan = planRepairs(bundle, report: diagnose(bundle))
        let mode = plan.items.first { $0.id == "clash-global-to-rule" }
        XCTAssertEqual(mode?.risk, .high)
        XCTAssertEqual(mode?.initiallyChecked, false)
        XCTAssertTrue(plan.items.filter { $0.risk == .safe && $0.executable }.allSatisfy(\.initiallyChecked))
        XCTAssertTrue(plan.items.filter { $0.risk == .high }.allSatisfy { !$0.initiallyChecked })
    }

    func testConfirmStartsUnsatisfied() {
        let items = [
            RepairItem(id: "a", hop: 5, title: "关闭代理", currentValue: "开", newValue: "关", risk: .safe, commands: [
                .setWebProxyState(service: "Wi-Fi", enabled: false),
            ]),
        ]
        XCTAssertFalse(RepairConfirmation.canApply(items: items, checked: ["a"], confirmed: false, highRiskConfirmed: false))
        XCTAssertTrue(RepairConfirmation.canApply(items: items, checked: ["a"], confirmed: true, highRiskConfirmed: false))
    }

    func testHighRiskNeedsSecondConfirm() {
        let items = [
            RepairItem(id: "a", hop: 6, title: "改模式", currentValue: "global", newValue: "rule", risk: .high, commands: [
                .clashSetMode(host: "127.0.0.1", port: 9090, mode: "rule"),
            ]),
        ]
        XCTAssertFalse(RepairConfirmation.canApply(items: items, checked: ["a"], confirmed: true, highRiskConfirmed: false))
        XCTAssertTrue(RepairConfirmation.canApply(items: items, checked: ["a"], confirmed: true, highRiskConfirmed: true))
    }

    func testQuickCleanDisabledWithoutReport() {
        XCTAssertFalse(RepairConfirmation.quickCleanEnabled(hasDiagnosis: false))
        XCTAssertTrue(RepairConfirmation.quickCleanEnabled(hasDiagnosis: true))
    }

    func testHealthyGlobalDoesNotOfferModeChange() {
        let bundle = DemoLibrary.clashGlobalHealthy()
        let plan = planRepairs(bundle, report: diagnose(bundle))
        XCTAssertNil(plan.items.first { $0.id == "clash-global-to-rule" })
    }

    func testForbiddenOperationsRejected() {
        let forbidden: [[String]] = [
            ["/usr/libexec/ApplicationFirewall/socketfilterfw", "--setglobalstate", "off"],
            ["/sbin/pfctl", "-d"],
            ["/sbin/route", "-n", "flush"],
            ["/sbin/route", "flush"],
            ["/usr/bin/security", "add-trusted-cert", "-d", "-r", "trustRoot", "evil.cer"],
            ["/bin/sh", "-c", "echo 1.2.3.4 bad >> /etc/hosts"],
            ["/usr/bin/security", "delete-keychain", "login.keychain"],
            ["/usr/sbin/networksetup", "-removepreferred", "Wi-Fi"],
            ["/usr/sbin/networksetup", "-removenetworkservice", "Wi-Fi"],
            ["/usr/sbin/scutil", "--nc", "delete", "Cisco AnyConnect"],
            ["/usr/sbin/networksetup", "-setwebproxy", "Wi-Fi", "evil.example", "8080"],
            ["/usr/sbin/networksetup", "-setsecurewebproxy", "Wi-Fi", "8.8.8.8", "7890"],
            ["/bin/rm", "-rf", "/Applications/Clash Verge.app"],
        ]
        for argv in forbidden {
            XCTAssertFalse(RepairGuard.allowsArgv(argv, phase: .repair, snapshot: nil), argv.joined(separator: " "))
            XCTAssertFalse(RepairGuard.allowsArgv(argv, phase: .rollback, snapshot: nil), argv.joined(separator: " "))
        }
    }

    func testUnstructuredShellRejected() {
        let samples = [
            "networksetup -setwebproxystate Wi-Fi off",
            "socketfilterfw --setglobalstate off",
            "route -n flush",
            "echo x >> /etc/hosts",
        ]
        for sample in samples {
            XCTAssertFalse(RepairGuard.allowsUnstructuredShell(sample))
        }
    }

    func testRollbackRestoresSameProxy() throws {
        let bundle = DemoLibrary.leftoverProxy()
        let snapshot = makeSnapshot(bundle)
        let commands = rollbackCommands(for: snapshot)
        XCTAssertTrue(commands.contains {
            if case .setWebProxy(let service, let host, let port) = $0 {
                return service == "Wi-Fi" && host == "127.0.0.1" && port == 7890
            }
            return false
        })
        for command in commands {
            XCTAssertNoThrow(try RepairGuard.validate(command, phase: .rollback, snapshot: snapshot))
        }
        XCTAssertThrowsError(try RepairGuard.validate(
            .setWebProxy(service: "Wi-Fi", host: "127.0.0.1", port: 7890),
            phase: .repair,
            snapshot: snapshot
        ))
    }

    func testRollbackRejectsUnknownProxy() {
        let snapshot = makeSnapshot(DemoLibrary.leftoverProxy())
        XCTAssertThrowsError(try RepairGuard.validate(
            .setWebProxy(service: "Wi-Fi", host: "evil.example", port: 8080),
            phase: .rollback,
            snapshot: snapshot
        ))
        XCTAssertFalse(RepairGuard.allowsArgv(
            ["/usr/sbin/networksetup", "-setwebproxy", "Wi-Fi", "evil.example", "8080"],
            phase: .rollback,
            snapshot: snapshot
        ))
    }

    func testNoDemoPlanIssuesForbiddenCommand() throws {
        for bundle in DemoLibrary.allBundles() {
            let report = diagnose(bundle)
            let plan = planRepairs(bundle, report: report)
            for item in plan.items {
                for command in item.commands {
                    XCTAssertNoThrow(try RepairGuard.validate(command, phase: .repair, snapshot: nil))
                    if command.isClash { continue }
                    let argv = RepairGuard.argv(for: command)
                    XCTAssertTrue(RepairGuard.allowsArgv(argv, phase: .repair, snapshot: nil), argv.joined(separator: " "))
                    let text = argv.joined(separator: " ").lowercased()
                    XCTAssertFalse(text.contains("flush"))
                    XCTAssertFalse(text.contains("hosts"))
                    XCTAssertFalse(text.contains("socketfilterfw"))
                    XCTAssertFalse(text.contains("pfctl"))
                    XCTAssertFalse(text.contains("keychain"))
                    XCTAssertFalse(text.contains("trusted-cert"))
                    XCTAssertFalse(text.contains("removepreferred"))
                    XCTAssertFalse(text.contains("delete"))
                    XCTAssertFalse(text.contains("uninstall"))
                }
            }
        }
    }

    func testClashModeOnlyLoopbackRule() {
        XCTAssertNoThrow(try RepairGuard.validate(
            .clashSetMode(host: "127.0.0.1", port: 9090, mode: "rule"),
            phase: .repair,
            snapshot: nil
        ))
        XCTAssertThrowsError(try RepairGuard.validate(
            .clashSetMode(host: "10.1.1.1", port: 9090, mode: "rule"),
            phase: .repair,
            snapshot: nil
        ))
        XCTAssertThrowsError(try RepairGuard.validate(
            .clashSetMode(host: "127.0.0.1", port: 9090, mode: "global"),
            phase: .repair,
            snapshot: nil
        ))
    }

    func testDHCPRenewOnlyOnPhysicalInterface() throws {
        let bundle = DemoLibrary.linkLocal()
        let plan = planRepairs(bundle, report: diagnose(bundle))
        let renew = plan.items.first { $0.id == "renew-en0" }
        XCTAssertNotNil(renew)
        XCTAssertEqual(renew?.commands, [.renewDHCP(interface: "en0")])
        XCTAssertTrue(RepairGuard.allowsArgv(["/usr/sbin/ipconfig", "set", "en0", "DHCP"], phase: .repair, snapshot: nil))
        XCTAssertFalse(RepairGuard.allowsArgv(["/usr/sbin/ipconfig", "set", "utun3", "DHCP"], phase: .repair, snapshot: nil))
        XCTAssertFalse(RepairGuard.allowsArgv(["/usr/sbin/ipconfig", "set", "en0", "NONE"], phase: .repair, snapshot: nil))
    }

    func testDisconnectVPNDoesNotDelete() throws {
        var draft = Draft()
        draft.scope = .global
        draft.gatewayOK = true
        draft.domesticOK = true
        draft.foreignViaOK = false
        draft.viaAttempted = true
        draft.services[0].https = (true, "127.0.0.1", 6152)
        draft.listeners = [ListenerDraft(process: "Surge", host: "127.0.0.1", port: 6152)]
        draft.processes = ["/Applications/Surge.app/Contents/MacOS/Surge"]
        draft.vpns = [VPNDraft(connected: true, name: "Cisco AnyConnect", kind: "com.cisco.anyconnect")]
        let bundle = draft.make()
        let plan = planRepairs(bundle, report: diagnose(bundle))
        let stop = try XCTUnwrap(plan.items.first { $0.id == "stop-vpn-Cisco AnyConnect" })
        XCTAssertEqual(stop.risk, .high)
        XCTAssertEqual(stop.commands, [.stopSystemVPN(service: "Cisco AnyConnect")])
        let argv = RepairGuard.argv(for: .stopSystemVPN(service: "Cisco AnyConnect"))
        XCTAssertEqual(argv, ["/usr/sbin/scutil", "--nc", "stop", "Cisco AnyConnect"])
        XCTAssertTrue(RepairGuard.allowsArgv(argv, phase: .repair, snapshot: nil))
        XCTAssertFalse(RepairGuard.allowsArgv(["/usr/sbin/scutil", "--nc", "delete", "Cisco AnyConnect"], phase: .repair, snapshot: nil))
    }

    func testStaleRouteDoesNotFlush() {
        let bundle = DemoLibrary.staleUtun()
        let plan = planRepairs(bundle, report: diagnose(bundle))
        let notice = plan.items.first { $0.id == "notice-no-route-flush" }
        XCTAssertEqual(notice?.noticeOnly, true)
        XCTAssertTrue(notice?.commands.isEmpty == true)
        XCTAssertTrue(notice?.newValue.contains("route flush") == true || notice?.newValue.contains("禁止") == true)
        XCTAssertFalse(plan.items.contains { item in
            item.commands.contains { command in
                RepairGuard.argv(for: command).contains("route")
            }
        })
    }

    func testHistoryRoundTripAndPrune() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tongbulian-history-\(UUID().uuidString)")
        let store = HistoryStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let report = diagnose(DemoLibrary.cleanWiFi(), now: now)
        let fresh = historyEvent(from: report, trigger: .detect, at: now.addingTimeInterval(-60 * 60))
        let old = historyEvent(from: report, trigger: .periodic, at: now.addingTimeInterval(-25 * 60 * 60))
        store.append(fresh, now: now)
        store.append(old, now: now)
        let loaded = store.load(now: now)
        XCTAssertEqual(loaded.map(\.id), [fresh.id])
        XCTAssertEqual(loaded.first?.diagram.nodes.isEmpty, false)
        XCTAssertEqual(loaded.first?.hops.count, 8)
        XCTAssertEqual(loaded.first?.trigger, .detect)
        try? FileManager.default.removeItem(at: directory)
    }

    func testShanghaiClock() {
        let formatted = ShanghaiClock.format(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(formatted, "1970-01-01 08:00:00 Asia/Shanghai")
    }

    func testHistoryEventCarriesDiagramAndFields() {
        let report = diagnose(DemoLibrary.proxyOn(), now: Date(timeIntervalSince1970: 0))
        let event = historyEvent(from: report, trigger: .stateChange, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(event.linkKind, "Wi-Fi")
        XCTAssertEqual(event.ssid, "MizLab")
        XCTAssertEqual(event.ip, "192.168.1.23")
        XCTAssertEqual(event.gateway, "192.168.1.1")
        XCTAssertFalse(event.dns.isEmpty)
        XCTAssertTrue(event.systemProxyOn)
        XCTAssertEqual(event.systemProxyPort, 7890)
        XCTAssertTrue(event.vpnClient?.contains("Clash Verge") == true)
        XCTAssertEqual(event.pathModel, .ruleSplit)
        XCTAssertEqual(event.hopSummary.count, 8)
        XCTAssertFalse(event.diagram.edges.isEmpty)
        XCTAssertTrue(ShanghaiClock.format(event.recordedAt).contains("Asia/Shanghai"))
    }

    func testDryRunPrintsHopsWithoutCommands() {
        let text = DryRun.render(diagnose(DemoLibrary.leftoverProxy(), now: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(text.contains("通不连 干跑"))
        XCTAssertTrue(text.contains("不修改"))
        for index in 1...8 {
            XCTAssertTrue(text.contains("\(index)\t"))
        }
        XCTAssertTrue(text.contains("断"))
        XCTAssertTrue(text.contains("未知") || text.contains("残留") || text.contains("通"))
        XCTAssertFalse(text.contains("networksetup"))
        XCTAssertFalse(text.contains("ipconfig"))
        XCTAssertFalse(text.contains("socketfilterfw"))
        XCTAssertFalse(text.lowercased().contains("route -n"))
        XCTAssertTrue(text.contains("不会自动切换"))
    }

    func testSignatureIgnoresHop8() {
        let local = diagnose(DemoLibrary.cleanWiFi(scope: .local))
        var globalBundle = DemoLibrary.cleanWiFi(scope: .global)
        globalBundle.domesticDirectOK = true
        globalBundle.foreignDirectOK = true
        let global = diagnose(globalBundle)
        XCTAssertEqual(networkSignature(local), networkSignature(global))
        XCTAssertNotEqual(networkSignature(local, includeHop8: true), networkSignature(global, includeHop8: true))
    }
}
