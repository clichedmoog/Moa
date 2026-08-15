import AppKit
import MoaKit

/// 샌드박스 환경에서 rename 과 부모 디렉터리 쓰기가 가능한지 확인하는 일회용 앱.
/// 검증이 끝나면 이 타깃을 삭제한다.
final class ProbeView: NSView {
    let log = NSTextView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil) as? [URL] else { return false }

        for url in urls {
            let path = PathBytes(Array(url.path.utf8))
            append("── 드롭됨: \(path.displayString)")

            // 리스크 1: 이름 변경
            let outcome = Renamer.normalizeName(at: path)
            append("  rename 결과: \(outcome)")

            // 리스크 2: 부모 디렉터리에 새 파일 쓰기
            let parent = path.removingLastComponent()
            let probeFile = parent.appending(Array("moa-write-probe.tmp".utf8))
            let fd = probeFile.withCString { open($0, O_CREAT | O_WRONLY | O_TRUNC, 0o644) }
            if fd >= 0 {
                close(fd)
                _ = probeFile.withCString { unlink($0) }
                append("  부모 디렉터리 쓰기: 성공")
            } else {
                append("  부모 디렉터리 쓰기: 실패 errno=\(errno) (1=EPERM, 13=EACCES)")
            }
        }
        return true
    }

    func append(_ line: String) {
        log.string += line + "\n"
        NSLog("%@", line)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var probe: ProbeView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Moa 샌드박스 실측"
        probe = ProbeView(frame: window.contentView!.bounds)
        probe.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.documentView = probe.log
        probe.log.isEditable = false
        probe.addSubview(scroll)

        window.contentView = probe
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 샌드박스가 실제로 켜져 있는지 확인한다.
        // 샌드박스 상태에서는 홈 디렉터리가 컨테이너 경로로 바뀐다.
        let home = NSHomeDirectory()
        let sandboxed = home.contains("/Library/Containers/")
        probe.append("샌드박스 활성: \(sandboxed)")
        probe.append("홈 경로: \(home)")
        probe.append(sandboxed ? "→ 유효한 테스트다. 파일을 드롭하라."
                               : "→ 샌드박스가 꺼져 있다. 서명을 확인하라. 결과는 무의미하다.")
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
