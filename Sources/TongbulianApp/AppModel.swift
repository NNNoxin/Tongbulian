import Foundation
import Combine
import CoreLocation

@MainActor
final class AppModel: ObservableObject {
    @Published var scope: DetectScope {
        didSet {
            guard live else { return }
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey)
        }
    }
    @Published var report: DiagnosisReport?
    @Published var bundle: ProbeBundle?
    @Published var plan: RepairPlan?
    @Published var busy = false
    @Published var statusLine = "还没有检测"
    @Published var lastError: String?
    @Published var history: [HistoryEvent] = []
    @Published var selectedHistoryID: String?
    @Published var confirmRepair = false
    @Published var confirmHighRisk = false
    @Published var confirmRollback = false
    @Published var checked: Set<String> = []
    @Published var beforeDiagram: PathDiagram?
    @Published var afterDiagram: PathDiagram?
    @Published var repairLog = ""
    @Published private(set) var canRollback = false

    let live: Bool
    private let store: HistoryStore
    private let rollbackURL: URL
    private var snapshot: RepairSnapshot?
    private var timer: Timer?
    private var lastSignature: String?
    private let location = LocationGate()

    static let scopeKey = "Tongbulian.detectScope"

    init(live: Bool = true, directory: URL? = nil) {
        self.live = live
        let folder = directory ?? Self.supportDirectory(live: live)
        store = HistoryStore(directory: folder)
        rollbackURL = folder.appendingPathComponent("rollback.json")
        if let raw = UserDefaults.standard.string(forKey: Self.scopeKey), let saved = DetectScope(rawValue: raw) {
            scope = saved
        } else {
            scope = .local
        }
        history = store.load()
        restoreRollback()
        guard live else { return }
        location.request()
        let timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.periodicSample()
            }
        }
        self.timer = timer
    }

    var symbol: String {
        guard let report else { return "network" }
        if report.hops.contains(where: { $0.verdict == .duan }) { return "network.slash" }
        if report.hops.contains(where: { $0.verdict == .partial }) { return "wifi.exclamationmark" }
        return "network"
    }

    var canApplyRepair: Bool {
        guard report != nil, let plan else { return false }
        return RepairConfirmation.canApply(
            items: plan.items,
            checked: checked,
            confirmed: confirmRepair,
            highRiskConfirmed: confirmHighRisk
        )
    }

    func detect() {
        guard live, !busy else { return }
        busy = true
        lastError = nil
        statusLine = scope == .local ? "正在做局部检测" : "正在做全局检测"
        let scope = self.scope
        Task.detached {
            let bundle = MacCollector.collect(scope: scope)
            let report = diagnose(bundle)
            let plan = planRepairs(bundle, report: report)
            await MainActor.run {
                self.finish(bundle: bundle, report: report, plan: plan, trigger: .detect, replaceUI: true)
            }
        }
    }

    func periodicSample() {
        guard live, !busy else { return }
        busy = true
        Task.detached {
            let bundle = MacCollector.collect(scope: .local)
            let report = diagnose(bundle)
            await MainActor.run {
                let signature = networkSignature(report)
                let trigger: HistoryTrigger = signature == self.lastSignature ? .periodic : .stateChange
                let replace = self.report == nil || trigger == .stateChange
                self.finish(bundle: bundle, report: report, plan: planRepairs(bundle, report: report), trigger: trigger, replaceUI: replace)
                if !replace {
                    self.statusLine = "定时记录已写入本机，窗口仍保留上一次检测"
                }
            }
        }
    }

    func toggle(_ id: String, on: Bool) {
        if on { checked.insert(id) } else { checked.remove(id) }
    }

    func applyRepair() {
        guard live, !busy, let bundle, let plan, canApplyRepair else { return }
        let chosen = plan.items.filter { checked.contains($0.id) && $0.executable }
        let commands = chosen.flatMap(\.commands)
        guard !commands.isEmpty else { return }
        busy = true
        lastError = nil
        statusLine = "正在按预览修改。系统可能会询问管理员密码。"
        let before = report?.diagram
        let taken = makeSnapshot(bundle)
        let scope = self.scope
        Task.detached {
            do {
                let log = try RepairRunner.apply(commands, phase: .repair, snapshot: nil)
                await MainActor.run {
                    self.snapshot = taken
                    self.beforeDiagram = before
                    self.persistRollback()
                    self.repairLog = log
                    self.confirmRepair = false
                    self.confirmHighRisk = false
                    self.busy = false
                    self.redetect(scope: scope, status: "修复完成，正在重新检测")
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.lastError = "\(error)"
                    self.statusLine = "修复没有完成"
                }
            }
        }
    }

    func rollback() {
        guard live, !busy, confirmRollback, let snapshot else { return }
        let commands = rollbackCommands(for: snapshot)
        busy = true
        lastError = nil
        statusLine = "正在撤回。系统可能会再问一次管理员密码。"
        let scope = self.scope
        let saved = snapshot
        Task.detached {
            do {
                let log = try RepairRunner.apply(commands, phase: .rollback, snapshot: saved)
                await MainActor.run {
                    self.repairLog = log
                    self.snapshot = nil
                    self.canRollback = false
                    self.confirmRollback = false
                    try? FileManager.default.removeItem(at: self.rollbackURL)
                    self.busy = false
                    self.redetect(scope: scope, status: "已撤回，正在重新检测")
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.lastError = "\(error)"
                    self.statusLine = "撤回没有完成"
                }
            }
        }
    }

    private func redetect(scope: DetectScope, status: String) {
        guard live else { return }
        busy = true
        statusLine = status
        Task.detached {
            let bundle = MacCollector.collect(scope: scope)
            let report = diagnose(bundle)
            await MainActor.run {
                self.afterDiagram = report.diagram
                self.finish(bundle: bundle, report: report, plan: planRepairs(bundle, report: report), trigger: .detect, replaceUI: true)
            }
        }
    }

    private func finish(bundle: ProbeBundle, report: DiagnosisReport, plan: RepairPlan, trigger: HistoryTrigger, replaceUI: Bool) {
        let event = historyEvent(from: report, trigger: trigger, at: report.generatedAt)
        store.append(event)
        history = store.load()
        lastSignature = networkSignature(report)
        busy = false
        if replaceUI {
            self.bundle = bundle
            self.report = report
            self.plan = plan
            checked = RepairConfirmation.initialChecked(plan.items)
            confirmRepair = false
            confirmHighRisk = false
            statusLine = "\(ShanghaiClock.format(report.generatedAt)) · \(report.scope.title) · \(report.pathModel.rawValue)"
        }
    }

    private func persistRollback() {
        guard let snapshot, let beforeDiagram else { return }
        let record = RollbackFile(snapshot: snapshot, before: beforeDiagram)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: rollbackURL, options: .atomic)
        }
        canRollback = true
    }

    private func restoreRollback() {
        guard let data = try? Data(contentsOf: rollbackURL),
              let record = try? JSONDecoder().decode(RollbackFile.self, from: data) else { return }
        snapshot = record.snapshot
        beforeDiagram = record.before
        canRollback = true
    }

    private static func supportDirectory(live: Bool) -> URL {
        if !live {
            return FileManager.default.temporaryDirectory.appendingPathComponent("tongbulian-preview-\(UUID().uuidString)", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Tongbulian", isDirectory: true)
    }

    static func previewModel() -> AppModel {
        let model = AppModel(live: false)
        let bundle = DemoLibrary.leftoverProxy()
        let report = diagnose(bundle, now: Date(timeIntervalSince1970: 1_700_000_000))
        model.bundle = bundle
        model.report = report
        model.plan = planRepairs(bundle, report: report)
        model.checked = RepairConfirmation.initialChecked(model.plan?.items ?? [])
        model.history = [historyEvent(from: report, trigger: .detect, at: report.generatedAt)]
        model.statusLine = "预览数据，不会改这台机器"
        return model
    }
}

private struct RollbackFile: Codable {
    var snapshot: RepairSnapshot
    var before: PathDiagram
}

final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    func request() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }
}
