import AppKit

/// Dock 아이콘에 드롭된 항목을 받는다.
///
/// AppKit 이 `application(_:open:)`을 메인 스레드에서 부른다는 보장에 기대고 있었으므로,
/// 그 가정을 컴파일러가 강제하도록 클래스 전체를 `@MainActor`로 못박는다. `DropCoordinator`도
/// 이미 `@MainActor`라 여기서 `Task` 홉을 거칠 필요가 없다 — 그 홉이 있으면 연속으로
/// 들어온 Dock 드롭이 실행 순서 보장 없이 뒤섞이기 쉬웠다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// `MoaApp` 이 주입한다. 창이 뜨기 전에 드롭이 도착할 수 있으므로 큐에 담아둔다.
    var coordinator: DropCoordinator?
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator else {
            pending.append(contentsOf: urls)
            return
        }
        coordinator.handleFromDock(urls: urls)
        // 처리 결과는 창에만 나타난다. 창이 뒤에 있거나 최소화돼 있으면
        // 사용자는 드롭했는데 아무 반응이 없다고 느낀다.
        showMainWindow()
    }

    /// 창이 준비된 뒤 밀린 드롭을 흘려보낸다.
    func flushPending() {
        guard let coordinator, !pending.isEmpty else { return }
        let urls = pending
        pending.removeAll()
        coordinator.handleFromDock(urls: urls)
    }

    /// 마지막 창을 닫으면 앱을 끝낸다. 창이 하나뿐인 도구라 창 없이 남아 있을 이유가 없고,
    /// Dock 아이콘에 드롭하면 어차피 다시 실행된다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Dock 아이콘을 클릭했는데 창이 없으면 다시 띄운다.
    /// (창을 닫았지만 종료 직전이라 아직 살아 있는 순간에 도달할 수 있다.)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    /// 숨겨졌거나 최소화된 창을 앞으로 가져온다. Dock 드롭으로 앱이 깨어났을 때
    /// 결과가 보이지 않으면 아무 일도 안 일어난 것처럼 보인다.
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
