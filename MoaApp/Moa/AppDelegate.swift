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
        coordinator.handle(urls: urls)
    }

    /// 창이 준비된 뒤 밀린 드롭을 흘려보낸다.
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
