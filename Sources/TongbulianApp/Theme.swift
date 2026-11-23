import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case overview = "总览"
    case hops = "环详情"
    case path = "流量路径"
    case repair = "清残留"
    case history = "历史"

    var id: String { rawValue }

    var fullTitle: String {
        switch self {
        case .overview: return "总览"
        case .hops: return "环详情"
        case .path: return "流量路径"
        case .repair: return "清残留预览"
        case .history: return "网络状态历史"
        }
    }
}

enum ToneColor {
    static func color(_ tone: Tone) -> Color {
        switch tone {
        case .ok: return Color(red: 0.09, green: 0.46, blue: 0.29)
        case .bad: return Color(red: 0.70, green: 0.16, blue: 0.16)
        case .warn: return Color(red: 0.67, green: 0.40, blue: 0.05)
        case .muted: return Color.secondary
        case .info: return Color(red: 0.16, green: 0.34, blue: 0.58)
        }
    }

    static func color(_ verdict: HopVerdict) -> Color {
        switch verdict {
        case .tong: return color(.ok)
        case .duan: return color(.bad)
        case .partial: return color(.warn)
        case .unknown: return color(.muted)
        }
    }
}

struct VerdictPill: View {
    var verdict: HopVerdict

    var body: some View {
        Text(verdict.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ToneColor.color(verdict))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ToneColor.color(verdict).opacity(0.12), in: Capsule())
    }
}

struct QuietCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
