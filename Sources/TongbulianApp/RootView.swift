import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: AppTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
            Divider()
            Group {
                switch tab {
                case .overview: OverviewView()
                case .hops: HopDetailView()
                case .path: PathView()
                case .repair: RepairView()
                case .history: HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 420, height: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("通不连")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if let modelName = model.report?.pathModel.rawValue {
                    Text(modelName)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            Text(model.statusLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(ToneColor.color(.bad))
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AppTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tab == item ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.fullTitle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let report = model.report {
                        QuietCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(report.pathFootnote)
                                    .font(.system(size: 12))
                                Text(report.conflict.workBuddy)
                                    .font(.system(size: 12))
                                Text(report.conflict.claudeAndChatGPT)
                                    .font(.system(size: 12))
                                Text(report.conflict.refusal)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(report.hops) { hop in
                            hopRow(hop)
                        }
                    } else {
                        QuietCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("先看八环，再决定要不要动系统。")
                                    .font(.system(size: 13, weight: .medium))
                                Text("局部检测不访问公网。全局检测才会比较网关、境内直连、境外 443，以及走隧道的同一目标。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            bottomBar
        }
    }

    private func hopRow(_ hop: HopResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(hop.index)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 18, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(hop.title)
                    .font(.system(size: 13, weight: .medium))
                Text(hop.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VerdictPill(verdict: hop.verdict)
        }
        .padding(.vertical, 4)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("检测范围", selection: $model.scope) {
                Text("局部检测").tag(DetectScope.local)
                Text("全局检测").tag(DetectScope.global)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(model.scope == .local ? "只做 1–7 环，可以离线。第 8 环保持未知。" : "额外比较境内直连、境外 443 和经隧道的同一目标。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button(action: model.detect) {
                HStack {
                    Spacer()
                    if model.busy {
                        ProgressView().controlSize(.small)
                        Text("检测中")
                    } else {
                        Text("重新检测")
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || !model.live)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(16)
    }
}

struct HopDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected = 1

    var body: some View {
        if let report = model.report {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("环", selection: $selected) {
                        ForEach(report.hops) { hop in
                            Text("\(hop.index) \(hop.title)").tag(hop.index)
                        }
                    }
                    .labelsHidden()
                    if let hop = report.hops.first(where: { $0.index == selected }) {
                        HStack {
                            Text(hop.title).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            VerdictPill(verdict: hop.verdict)
                        }
                        Text(hop.summary).font(.system(size: 13))
                        if hop.inferred {
                            Text("这一环含有推断。").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if let gap = hop.informationGap {
                            Text("信息缺口：\(gap)")
                                .font(.system(size: 12))
                                .foregroundStyle(ToneColor.color(.warn))
                        }
                        ForEach(Array(hop.evidence.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(16)
            }
        } else {
            empty("检测之后，这里按环列出证据。")
        }
    }
}

struct PathView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let report = model.report {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(report.pathModel.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                    Text(report.pathFootnote)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    DiagramView(diagram: report.diagram)
                    QuietCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("两条路不要自动切换")
                                .font(.system(size: 12, weight: .semibold))
                            Text(report.conflict.workBuddy).font(.system(size: 12))
                            Text(report.conflict.claudeAndChatGPT).font(.system(size: 12))
                        }
                    }
                }
                .padding(16)
            }
        } else {
            empty("检测之后，这里按当前状态重画路径。")
        }
    }
}

struct DiagramView: View {
    var diagram: PathDiagram

    var body: some View {
        let rows = Dictionary(grouping: diagram.nodes, by: \.row)
        let keys = rows.keys.sorted()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(rows[key, default: []].sorted { $0.column < $1.column }) { node in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(node.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ToneColor.color(node.tone).opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(ToneColor.color(node.tone).opacity(0.55), lineWidth: 1)
                        )
                    }
                }
                if index < keys.count - 1 {
                    connector(fromRow: key)
                }
            }
            ForEach(diagram.footnotes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private func connector(fromRow row: Int) -> some View {
        let ids = Set(diagram.nodes.filter { $0.row == row }.map(\.id))
        let edges = diagram.edges.filter { ids.contains($0.from) }
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(edges) { edge in
                HStack(spacing: 6) {
                    Path { path in
                        path.move(to: CGPoint(x: 1, y: 0))
                        path.addLine(to: CGPoint(x: 1, y: 14))
                    }
                    .stroke(
                        ToneColor.color(edge.tone),
                        style: StrokeStyle(lineWidth: 1.4, dash: edge.inferred ? [3, 3] : [])
                    )
                    .frame(width: 8, height: 14)
                    Text(edge.label + (edge.inferred ? " · 推断" : ""))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(edge.to)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct RepairView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("先有诊断，才允许清残留。每一项都写成「现在 → 改成」。确认框一开始不勾。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if model.report == nil {
                    QuietCard {
                        Text("还没有诊断。一键清残留保持关闭。")
                            .font(.system(size: 13, weight: .medium))
                    }
                } else if let plan = model.plan {
                    Text(plan.headline)
                        .font(.system(size: 12))
                    if plan.items.isEmpty {
                        Text("这次没有要改的项目。")
                            .font(.system(size: 13))
                    }
                    ForEach(plan.items) { item in
                        itemRow(item)
                    }
                    Toggle("我看过上面的预览，确认执行勾选的项目", isOn: $model.confirmRepair)
                        .font(.system(size: 12))
                        .disabled(!model.live)
                    if plan.items.contains(where: { model.checked.contains($0.id) && $0.risk == .high && $0.executable }) {
                        Toggle("勾选里有高风险项。我再确认一次", isOn: $model.confirmHighRisk)
                            .font(.system(size: 12))
                            .disabled(!model.live)
                    }
                }
                Button(action: model.applyRepair) {
                    Text("一键清残留")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.live || model.busy || !RepairConfirmation.quickCleanEnabled(hasDiagnosis: model.report != nil) || !model.canApplyRepair)

                if model.canRollback {
                    Divider()
                    Text("撤回这次修复")
                        .font(.system(size: 13, weight: .semibold))
                    Text("用修复前的快照把代理、DNS、PAC、WPAD、系统 VPN 连接和 Clash 模式放回去。不会删除描述文件。DHCP 续租没有旧租约可还原。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let before = model.beforeDiagram {
                        Text("修复前").font(.system(size: 12, weight: .semibold))
                        DiagramView(diagram: before)
                    }
                    if let after = model.afterDiagram {
                        Text("修复后").font(.system(size: 12, weight: .semibold))
                        DiagramView(diagram: after)
                    }
                    Toggle("我确认撤回本次修复", isOn: $model.confirmRollback)
                        .font(.system(size: 12))
                        .disabled(!model.live)
                    Button("撤回本次修复", action: model.rollback)
                        .disabled(!model.live || model.busy || !model.confirmRollback)
                }
                if !model.repairLog.isEmpty {
                    Text(model.repairLog)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
        }
    }

    private func itemRow(_ item: RepairItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { model.checked.contains(item.id) },
                set: { model.toggle(item.id, on: $0) }
            )) {
                HStack {
                    Text(item.title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(item.risk == .high ? "高风险" : "可先勾选")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.risk == .high ? ToneColor.color(.warn) : ToneColor.color(.ok))
                }
            }
            .disabled(item.noticeOnly || !model.live)
            Text("\(item.currentValue)  →  \(item.newValue)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(Array(item.commands.enumerated()), id: \.offset) { _, command in
                Text(preview(command))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func preview(_ command: RepairCommand) -> String {
        if case .clashSetMode(let host, let port, let mode) = command {
            return "PATCH http://\(host):\(port)/configs {\"mode\":\"\(mode)\"}"
        }
        return RepairGuard.argv(for: command).joined(separator: " ")
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let selected = model.history.first(where: { $0.id == model.selectedHistoryID }) {
            detail(selected)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("只存在这台 Mac 的「应用程序支持」目录里，超过 24 小时就删。不上传。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("手动检测都会记一笔。应用开着时，每 5 分钟做一次局部采样：有变化记为状态变化，没变化记为定时记录。定时采样不访问公网。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if model.history.isEmpty {
                    Text("还没有记录。做一次检测后，时间线会出现在这里。")
                        .font(.system(size: 13))
                        .padding(.top, 8)
                }
                ForEach(model.history) { event in
                    Button {
                        model.selectedHistoryID = event.id
                    } label: {
                        historyRow(event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func historyRow(_ event: HistoryEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(ToneColor.color(event.hopSummary.contains("断") ? .bad : .info))
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(ShanghaiClock.format(event.recordedAt))
                    .font(.system(size: 11, weight: .semibold))
                Text("\(event.trigger.rawValue) · \(event.pathModel.rawValue)")
                    .font(.system(size: 12))
                Text(line(event))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    ForEach(Array(event.hopSummary.enumerated()), id: \.offset) { _, verdict in
                        Text(verdict)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(color(verdict))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func detail(_ event: HistoryEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Button("返回时间线") { model.selectedHistoryID = nil }
                    .font(.system(size: 12))
                Text(ShanghaiClock.format(event.recordedAt))
                    .font(.system(size: 13, weight: .semibold))
                Text("\(event.trigger.rawValue) · \(event.pathModel.rawValue)")
                    .font(.system(size: 12))
                QuietCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("链路 \(event.linkKind)\(event.linkUp ? " · 已连接" : " · 未连接")")
                        Text("SSID \(event.ssid ?? "未知")")
                        Text("IP \(event.ip ?? "无") · 网关 \(event.gateway ?? "无")")
                        Text("DNS \(event.dns.isEmpty ? "无" : event.dns.joined(separator: "、"))")
                        Text(event.systemProxyOn ? "系统代理 \(event.systemProxyPort.map(String.init) ?? "")" : "系统代理关闭")
                        Text("客户端 \(event.vpnClient ?? "无")")
                        Text("隧道地址 \(event.tunnelAddress ?? "无")")
                    }
                    .font(.system(size: 12))
                }
                DiagramView(diagram: event.diagram)
                ForEach(event.hops) { hop in
                    HStack {
                        Text("\(hop.index) \(hop.title)")
                            .font(.system(size: 12))
                        Spacer()
                        VerdictPill(verdict: hop.verdict)
                    }
                    Text(hop.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func line(_ event: HistoryEvent) -> String {
        let ssid = event.ssid ?? event.linkKind
        let proxy = event.systemProxyOn ? "代理 \(event.systemProxyPort.map { ":\($0)" } ?? "")" : "代理关"
        let client = event.vpnClient ?? "无客户端"
        return "\(ssid) · \(event.ip ?? "无 IP") · \(proxy) · \(client)"
    }

    private func color(_ verdict: String) -> Color {
        switch verdict {
        case "通": return ToneColor.color(.tong)
        case "断": return ToneColor.color(.duan)
        case "部分": return ToneColor.color(.partial)
        default: return ToneColor.color(.unknown)
        }
    }
}

private func empty(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
}
