import Foundation

public enum DryRun {
    public static func render(_ report: DiagnosisReport) -> String {
        var lines: [String] = []
        lines.append("通不连 干跑")
        lines.append("时间：\(ShanghaiClock.format(report.generatedAt))")
        lines.append("范围：\(report.scope.title)")
        lines.append("干跑：只打印判断，不修改代理、DNS、路由或 VPN。")
        lines.append("路径：\(report.pathModel.rawValue)")
        lines.append(report.pathFootnote)
        lines.append("")
        for hop in report.hops {
            lines.append("\(hop.index)\t\(hop.verdict.rawValue)\t\(hop.title)\t\(hop.summary)")
            if let gap = hop.informationGap {
                lines.append("    信息缺口：\(gap)")
            }
            if hop.inferred {
                lines.append("    这一环含有推断")
            }
            for item in hop.evidence {
                lines.append("    - \(item)")
            }
        }
        lines.append("")
        lines.append("第 8 环判定：\(report.hop8.rawValue)")
        lines.append(report.conflict.workBuddy)
        lines.append(report.conflict.claudeAndChatGPT)
        lines.append(report.conflict.refusal)
        return lines.joined(separator: "\n")
    }
}
