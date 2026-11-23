import XCTest
@testable import TongDuanCore

final class ClassificationTests: XCTestCase {
    func testCleanWiFiIsDirectAndHopsOpen() {
        let report = diagnose(DemoLibrary.cleanWiFi())
        XCTAssertEqual(report.pathModel, .directClean)
        for index in 1...7 {
            XCTAssertEqual(hop(report, index).verdict, .tong, "hop \(index) \(hop(report, index).summary)")
        }
        XCTAssertEqual(hop(report, 8).verdict, .unknown)
        XCTAssertEqual(report.hop8, .notRun)
        XCTAssertFalse(report.conflict.willAutoSwitch)
    }

    func testCleanEthernet() {
        let report = diagnose(DemoLibrary.ethernetClean())
        XCTAssertEqual(hop(report, 1).verdict, .tong)
        XCTAssertTrue(hop(report, 1).summary.contains("以太网"))
        XCTAssertEqual(report.pathModel, .directClean)
    }

    func testSystemProxyListeningIsRuleSplit() {
        let report = diagnose(DemoLibrary.proxyOn())
        XCTAssertEqual(report.pathModel, .ruleSplit)
        XCTAssertEqual(hop(report, 5).verdict, .tong)
        XCTAssertEqual(hop(report, 6).verdict, .tong)
        XCTAssertTrue(hop(report, 5).evidence.joined().contains("7890"))
        XCTAssertTrue(hop(report, 6).summary.contains("Clash Verge"))
    }

    func testProxyWithoutAPIIsSystemProxy() {
        let report = diagnose(DemoLibrary.proxyWithoutAPI())
        XCTAssertEqual(report.pathModel, .systemProxy)
        XCTAssertEqual(hop(report, 6).verdict, .partial)
        XCTAssertNotNil(hop(report, 6).informationGap)
    }

    func testLeftoverProxy() {
        let report = diagnose(DemoLibrary.leftoverProxy())
        XCTAssertEqual(report.pathModel, .stale)
        XCTAssertEqual(hop(report, 5).verdict, .duan)
        XCTAssertTrue(hop(report, 5).summary.contains("没有进程"))
        XCTAssertEqual(report.hop8, .leftover)
    }

    func testLeftoverDNS() {
        let report = diagnose(DemoLibrary.leftoverDNS())
        XCTAssertEqual(hop(report, 4).verdict, .duan)
        XCTAssertTrue(hop(report, 4).summary.contains("127.0.0.1"))
        XCTAssertEqual(report.pathModel, .stale)
    }

    func testNoDefaultRoute() {
        let report = diagnose(DemoLibrary.noDefaultRoute())
        XCTAssertEqual(hop(report, 3).verdict, .duan)
        XCTAssertTrue(hop(report, 3).summary.contains("没有默认路由"))
    }

    func testBadDNSEmpty() {
        let report = diagnose(DemoLibrary.badDNS())
        XCTAssertEqual(hop(report, 4).verdict, .duan)
        XCTAssertTrue(hop(report, 4).summary.contains("没有读到可用 DNS"))
    }

    func testUTUNWithClientIsGlobal() {
        let report = diagnose(DemoLibrary.tunGlobal())
        XCTAssertEqual(report.pathModel, .tunGlobal)
        XCTAssertTrue(hop(report, 3).summary.contains("utun") || hop(report, 3).evidence.joined().contains("utun"))
    }

    func testRuleModeIsNotGlobal() {
        let report = diagnose(DemoLibrary.ruleSplit())
        XCTAssertEqual(report.pathModel, .ruleSplit)
        XCTAssertNotEqual(report.pathModel, .tunGlobal)
    }

    func testWiFiOff() {
        let report = diagnose(DemoLibrary.wifiOff())
        XCTAssertEqual(hop(report, 1).verdict, .duan)
        XCTAssertTrue(hop(report, 1).summary.contains("关闭"))
    }

    func testExternalProbeFailureIsNotOffline() {
        let report = diagnose(DemoLibrary.probesFailedOnly())
        XCTAssertEqual(report.hop8, .probesFailedOnly)
        XCTAssertEqual(hop(report, 8).verdict, .partial)
        XCTAssertTrue(hop(report, 8).summary.contains("探测"))
        XCTAssertFalse(hop(report, 8).summary.contains("上游没网"))
        XCTAssertFalse(hop(report, 8).summary.contains("没连上"))
        XCTAssertTrue(hop(report, 8).evidence.joined().contains("1.1.1.1"))
    }

    func testPingSuccessIsNotOnline() {
        let report = diagnose(DemoLibrary.pingIsNotOnline())
        XCTAssertEqual(report.hop8, .localUpstreamDown)
        XCTAssertEqual(hop(report, 8).verdict, .duan)
        XCTAssertTrue(hop(report, 8).summary.contains("上游") || hop(report, 8).summary.contains("境内直连"))
        XCTAssertTrue(hop(report, 8).evidence.joined().contains("1.1.1.1"))
        XCTAssertNotEqual(hop(report, 8).verdict, .tong)
    }

    func testLocalScopeHop8UnknownEvenIfProbesPresent() {
        let report = diagnose(DemoLibrary.localScopeIgnoresFilledProbes())
        XCTAssertEqual(report.scope, .local)
        XCTAssertEqual(hop(report, 8).verdict, .unknown)
        XCTAssertEqual(report.hop8, .notRun)
        XCTAssertTrue(hop(report, 8).informationGap?.contains("局部") == true)
        XCTAssertTrue(hop(report, 1).verdict != .unknown)
    }

    func testHop8GatewayUnreachableIsUpstream() {
        let report = diagnose(DemoLibrary.upstreamGateway())
        XCTAssertEqual(report.hop8, .localUpstreamDown)
        XCTAssertTrue(hop(report, 8).summary.contains("网关") || hop(report, 8).summary.contains("上游"))
        XCTAssertFalse(hop(report, 8).summary.contains("写错") && !hop(report, 8).summary.contains("不是"))
    }

    func testHop8DomesticDirectFailIsUpstream() {
        let report = diagnose(DemoLibrary.upstreamDomestic())
        XCTAssertEqual(report.hop8, .localUpstreamDown)
        XCTAssertTrue(hop(report, 8).summary.contains("境内直连"))
        XCTAssertTrue(hop(report, 8).summary.contains("不是代理"))
    }

    func testHop8ForeignPathDown() {
        let report = diagnose(DemoLibrary.foreignPath())
        XCTAssertEqual(report.hop8, .foreignPathDown)
        XCTAssertEqual(hop(report, 8).verdict, .duan)
        let summary = hop(report, 8).summary
        XCTAssertTrue(summary.contains("境外") || summary.contains("节点") || summary.contains("VPN"))
        XCTAssertFalse(summary.contains("没配置"))
        XCTAssertFalse(summary.contains("未配置"))
        XCTAssertFalse(summary.contains("没配"))
        XCTAssertTrue(hop(report, 8).evidence.joined().contains("境内直连"))
    }

    func testHop8LeftoverWhenDomesticDirectWorks() {
        let report = diagnose(DemoLibrary.hop8Leftover())
        XCTAssertEqual(report.hop8, .leftover)
        XCTAssertTrue(hop(report, 8).summary.contains("残留"))
        XCTAssertNotEqual(report.hop8, .localUpstreamDown)
    }

    func testHop8StaleUtun() {
        let report = diagnose(DemoLibrary.staleUtun())
        XCTAssertEqual(report.hop8, .leftover)
        XCTAssertEqual(report.pathModel, .stale)
        XCTAssertTrue(hop(report, 8).summary.contains("utun"))
        XCTAssertEqual(hop(report, 6).verdict, .duan)
    }

    func testHop8MissingProbesIsGap() {
        let report = diagnose(DemoLibrary.hop8Gap())
        XCTAssertEqual(report.hop8, .informationGap)
        XCTAssertEqual(hop(report, 8).verdict, .unknown)
        XCTAssertNotNil(hop(report, 8).informationGap)
    }

    func testCampusMixed() {
        let report = diagnose(DemoLibrary.campusMixed())
        XCTAssertEqual(report.pathModel, .campusMixed)
        XCTAssertTrue(hop(report, 5).evidence.joined().contains("WPAD"))
    }

    func testPACReported() {
        let report = diagnose(DemoLibrary.pac())
        XCTAssertEqual(hop(report, 5).verdict, .partial)
        XCTAssertTrue(hop(report, 5).evidence.joined().contains("PAC"))
        XCTAssertEqual(report.pathModel, .ruleSplit)
    }

    func testSOCKSProxy() {
        let report = diagnose(DemoLibrary.socksOnly())
        XCTAssertEqual(hop(report, 5).verdict, .tong)
        XCTAssertTrue(hop(report, 5).evidence.joined().contains("SOCKS"))
        XCTAssertEqual(report.pathModel, .ruleSplit)
    }

    func testDisabledServiceProxyNoted() {
        let report = diagnose(DemoLibrary.disabledServiceProxy())
        XCTAssertEqual(hop(report, 5).verdict, .partial)
        XCTAssertTrue(hop(report, 5).evidence.joined().contains("已停用"))
    }

    func testLinkLocalDHCP() {
        let report = diagnose(DemoLibrary.linkLocal())
        XCTAssertEqual(hop(report, 2).verdict, .duan)
        XCTAssertTrue(hop(report, 2).summary.contains("169.254") || hop(report, 2).summary.contains("DHCP"))
    }

    func testAnyConnectSplit() {
        let report = diagnose(DemoLibrary.anyConnect())
        XCTAssertEqual(hop(report, 6).verdict, .tong)
        XCTAssertTrue(hop(report, 6).summary.contains("AnyConnect"))
        XCTAssertEqual(report.pathModel, .splitTunnel)
    }

    func testTailscaleSplit() {
        let report = diagnose(DemoLibrary.tailscale())
        XCTAssertEqual(report.pathModel, .splitTunnel)
        XCTAssertTrue(hop(report, 6).evidence.joined().contains("Tailscale") || hop(report, 6).summary.contains("Tailscale"))
        XCTAssertTrue(hop(report, 6).evidence.joined().contains("拆分") || report.pathFootnote.contains("拆分") || report.pathModel == .splitTunnel)
    }

    func testWireGuardTakesDefault() {
        let report = diagnose(DemoLibrary.wireGuard())
        XCTAssertEqual(report.pathModel, .tunGlobal)
        XCTAssertTrue(hop(report, 6).summary.contains("WireGuard"))
    }

    func testSurgeRule() {
        let report = diagnose(DemoLibrary.surge())
        XCTAssertEqual(report.pathModel, .ruleSplit)
        XCTAssertTrue(hop(report, 6).summary.contains("Surge"))
    }

    func testSingBoxRule() {
        let report = diagnose(DemoLibrary.singBox())
        XCTAssertEqual(report.pathModel, .ruleSplit)
        XCTAssertTrue(hop(report, 6).summary.contains("sing-box"))
    }

    func testV2RayIsSystemProxyWithoutRuleClaim() {
        let report = diagnose(DemoLibrary.v2ray())
        XCTAssertEqual(report.pathModel, .systemProxy)
        XCTAssertNotEqual(report.pathModel, .ruleSplit)
        XCTAssertTrue(hop(report, 6).summary.contains("V2Ray"))
    }

    func testWeakSignal() {
        let report = diagnose(DemoLibrary.weakSignal())
        XCTAssertEqual(hop(report, 1).verdict, .partial)
        XCTAssertTrue(hop(report, 1).summary.contains("-85") || hop(report, 1).evidence.joined().contains("-85"))
    }

    func testTwoDefaultRoutes() {
        let report = diagnose(DemoLibrary.twoDefaults())
        XCTAssertEqual(hop(report, 3).verdict, .partial)
        XCTAssertEqual(report.pathModel, .tunGlobal)
    }

    func testClashAndSurgeConflict() {
        let report = diagnose(DemoLibrary.clashAndSurge())
        XCTAssertEqual(hop(report, 6).verdict, .partial)
        XCTAssertTrue(hop(report, 6).summary.contains("多个"))
    }

    func testATrust() {
        let report = diagnose(DemoLibrary.atrust())
        XCTAssertTrue(hop(report, 6).summary.contains("aTrust"))
        XCTAssertEqual(report.pathModel, .splitTunnel)
    }

    func testRemoteProxyUnverified() {
        let report = diagnose(DemoLibrary.remoteProxy())
        XCTAssertEqual(hop(report, 5).verdict, .partial)
        XCTAssertTrue(hop(report, 5).evidence.joined().contains("10.1.2.3"))
        XCTAssertEqual(report.pathModel, .systemProxy)
    }

    func testEveryEnabledServiceListed() {
        let report = diagnose(DemoLibrary.twoServices())
        let evidence = hop(report, 5).evidence.joined(separator: "\n")
        XCTAssertTrue(evidence.contains("Wi-Fi"))
        XCTAssertTrue(evidence.contains("Ethernet"))
    }

    func testClashGlobalMode() {
        let report = diagnose(DemoLibrary.clashGlobalHealthy())
        XCTAssertEqual(report.pathModel, .tunGlobal)
        XCTAssertTrue(report.pathFootnote.contains("global") || report.pathFootnote.contains("全局"))
        XCTAssertEqual(report.hop8, .reachable)
    }

    func testEmptyInputIsUnknown() {
        let report = diagnose(DemoLibrary.empty())
        XCTAssertEqual(report.pathModel, .unknown)
        XCTAssertTrue(report.hops.allSatisfy { $0.verdict == .unknown })
    }

    func testLocalDiagramMarksUnprobedEdgesInferred() {
        let report = diagnose(DemoLibrary.cleanWiFi())
        let domestic = report.diagram.edges.first { $0.id == "e-dom" }
        XCTAssertEqual(domestic?.inferred, true)
        XCTAssertTrue(report.diagram.nodes.contains { $0.id == "mac" })
    }

    func testConflictNeverAutoSwitches() {
        for bundle in DemoLibrary.allBundles() {
            let report = diagnose(bundle)
            XCTAssertFalse(report.conflict.willAutoSwitch)
            XCTAssertTrue(report.conflict.refusal.contains("不会自动切换"))
            XCTAssertFalse(report.conflict.workBuddy.isEmpty)
            XCTAssertFalse(report.conflict.claudeAndChatGPT.isEmpty)
        }
    }

    func testEightHopsAlwaysPresent() {
        for bundle in DemoLibrary.allBundles() {
            let report = diagnose(bundle)
            XCTAssertEqual(report.hops.map(\.index), [1, 2, 3, 4, 5, 6, 7, 8])
            XCTAssertTrue(report.hops.allSatisfy { !$0.summary.isEmpty && !$0.evidence.isEmpty })
        }
    }
}

func hop(_ report: DiagnosisReport, _ index: Int) -> HopResult {
    report.hops[index - 1]
}
