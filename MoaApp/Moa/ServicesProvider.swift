import AppKit

/// Finder 우클릭 → 서비스 에서 들어오는 요청을 받는다.
///
/// 왜 이 경로인가. 사용자가 원하는 건 "AirDrop 이나 메일로 보내기 전에 이름을 고치는 것"인데,
/// macOS 는 공유 흐름 **중간에** 앱을 끼워 넣지 못하게 막는다. 가능한 건 보내기 직전 한 단계고,
/// 그 자리에 가장 잘 맞는 관용구가 서비스(우클릭 메뉴)다. 파일을 고르고 → 모아쓰기 → 보낸다.
///
/// 샌드박스에서 동작하는 이유: 페이스트보드로 넘어온 파일 URL 에는 드롭과 마찬가지로
/// 암묵적 권한이 따라붙는다. 실측했다 — `startAccessingSecurityScopedResource()` 가
/// `false` 를 돌려주는데도 `rename(2)` 가 성공한다. 사용자가 메뉴에서 고른 행위 자체가
/// 권한 부여로 취급되기 때문이며, 따로 북마크를 저장해 둘 필요가 없다.
///
/// AppKit 이 서비스 핸들러를 메인 스레드에서 부르므로 `@MainActor` 로 못박는다.
/// `DropCoordinator` 가 `@MainActor` 라 여기서 홉을 거치면 연속 호출의 순서가 흐트러진다 —
/// `AppDelegate` 가 Dock 드롭에서 같은 이유로 같은 선택을 했다.
@MainActor
final class ServicesProvider: NSObject {

    /// `MoaApp` 이 주입한다. 앱이 서비스 호출로 처음 깨어나면 창보다 요청이 먼저 도착할 수 있다.
    var coordinator: DropCoordinator?
    weak var appDelegate: AppDelegate?

    /// 아직 coordinator 가 없을 때 대기시킨 요청. Dock 드롭과 같은 이유로 큐를 둔다.
    private var pending: [URL] = []

    /// Info.plist 의 `NSMessage` 와 이름이 정확히 일치해야 한다.
    /// 시그니처도 AppKit 이 기대하는 형태에서 벗어나면 조용히 호출되지 않는다.
    @objc func normalizeNames(_ pasteboard: NSPasteboard,
                              userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = Self.fileURLs(from: pasteboard)
        guard !urls.isEmpty else {
            // 여기까지 왔는데 URL 이 없다는 건 시스템이 우리가 선언하지 않은 타입을 보냈다는 뜻이다.
            // 조용히 넘어가면 사용자는 메뉴를 눌렀는데 아무 일도 안 일어난 것으로 본다.
            error.pointee = "고칠 파일을 읽지 못했습니다." as NSString
            return
        }
        deliver(urls)
    }

    /// 창이 준비된 뒤 밀린 요청을 흘려보낸다.
    func flushPending() {
        guard coordinator != nil, !pending.isEmpty else { return }
        let urls = pending
        pending.removeAll()
        deliver(urls)
    }

    private func deliver(_ urls: [URL]) {
        guard let coordinator else {
            pending.append(contentsOf: urls)
            return
        }
        coordinator.handle(urls: urls)
        // 결과는 창에만 나타난다. 서비스로 부르면 앱이 뒤에 있거나 아예 실행 중이 아니었을 수
        // 있으므로, 창을 앞으로 가져오지 않으면 사용자는 반응이 없다고 느낀다.
        appDelegate?.showMainWindow()
    }

    /// 페이스트보드에서 파일 URL 만 골라낸다.
    ///
    /// `NSPasteboard.readObjects` 는 `NSURL` 을 요구하면 웹 URL 도 함께 준다.
    /// 파일 이름을 고치는 도구이므로 파일이 아닌 것은 버린다.
    nonisolated static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (objects as? [URL] ?? []).filter(\.isFileURL)
    }
}
