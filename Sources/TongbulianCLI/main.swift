import Foundation
import TongDuanCore

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("-h") || arguments.contains("--help") || arguments.isEmpty {
    printUsage()
    exit(arguments.isEmpty ? 2 : 0)
}

if arguments.first == "diagnose" {
    let scope = scopeFlag(arguments) ?? .local
    if let name = value(after: "--demo", in: arguments) {
        guard var bundle = DemoLibrary.named(name) else {
            FileHandle.standardError.write(Data("未知示例 \(name)。可选：\(DemoLibrary.demoNames.joined(separator: ", "))\n".utf8))
            exit(2)
        }
        if let forced = scopeFlag(arguments) {
            bundle.scope = forced
        }
        emit(bundle)
        exit(0)
    }
    if let path = value(after: "--fixture", in: arguments) {
        let url = URL(fileURLWithPath: path)
        do {
            let data = try Data(contentsOf: url)
            var bundle = try JSONDecoder().decode(ProbeBundle.self, from: data)
            if arguments.contains("--scope") {
                bundle.scope = scope
            }
            emit(bundle)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("读不到夹具 \(path)：\(error)\n".utf8))
            exit(2)
        }
    }
    if arguments.contains("--dry-run") {
        FileHandle.standardError.write(Data("这台环境没有 macOS 采集器。请在 Mac 上运行菜单栏应用，或加上 --fixture / --demo。干跑不会改系统。\n".utf8))
        exit(2)
    }
    FileHandle.standardError.write(Data("diagnose 需要 --fixture、--demo，或在 macOS 应用里点「重新检测」。\n".utf8))
    exit(2)
}

FileHandle.standardError.write(Data("未知命令。\n".utf8))
printUsage()
exit(2)

func emit(_ bundle: ProbeBundle) {
    let report = diagnose(bundle, now: Date())
    print(DryRun.render(report))
    print("")
    print("路径模型：\(report.pathModel.rawValue)")
    print("第 8 环：\(report.hop8.rawValue)")
}

func scopeFlag(_ arguments: [String]) -> DetectScope? {
    guard let raw = value(after: "--scope", in: arguments) else { return nil }
    switch raw {
    case "local", "局部", "局部检测": return .local
    case "global", "全局", "全局检测": return .global
    default: return nil
    }
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func printUsage() {
    let text = """
    通不连 tongbulian — 干跑诊断，不修改系统

    用法
      tongbulian diagnose --demo <name> [--scope local|global]
      tongbulian diagnose --fixture <file.json> [--scope local|global]
      tongbulian diagnose --dry-run

    示例名：\(DemoLibrary.demoNames.joined(separator: ", "))

    局部检测只跑 1–7 环。全局检测才会解释第 8 环。
    这条命令不会关闭防火墙、不会改证书、不会改 hosts、不会刷新路由、不会删 VPN。
    """
    print(text)
}
