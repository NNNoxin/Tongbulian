import SwiftUI

@main
struct TongbulianApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(model)
        } label: {
            Label("通不连", systemImage: model.symbol)
        }
        .menuBarExtraStyle(.window)
    }
}
