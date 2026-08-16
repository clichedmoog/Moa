import AppKit
import SwiftUI

@main
struct MoaApp: App {
    @StateObject private var coordinator = DropCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    @EnvironmentObject var coordinator: DropCoordinator

    var body: some View {
        switch coordinator.state {
        case .idle:
            DropView()
        case .working:
            ProgressView("변환 중…")
                .frame(minWidth: 420, minHeight: 320)
        default:
            // 결과 화면은 Task 13 에서 만든다.
            DropView()
        }
    }
}
