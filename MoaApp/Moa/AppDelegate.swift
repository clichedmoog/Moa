import AppKit

/// Dock 아이콘에 드롭된 항목을 받는다.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// `MoaApp` 이 주입한다. 창이 뜨기 전에 드롭이 도착할 수 있으므로 큐에 담아둔다.
    var coordinator: DropCoordinator?
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator else {
            pending.append(contentsOf: urls)
            return
        }
        Task { @MainActor in coordinator.handle(urls: urls) }
    }

    /// 창이 준비된 뒤 밀린 드롭을 흘려보낸다.
    @MainActor
    func flushPending() {
        guard let coordinator, !pending.isEmpty else { return }
        let urls = pending
        pending.removeAll()
        coordinator.handle(urls: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
