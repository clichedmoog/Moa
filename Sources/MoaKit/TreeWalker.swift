import Foundation

public enum SkipReason: Equatable, Sendable {
    case symlink
    case bundle
    case hidden
}

public struct WalkItem: Equatable, Sendable {
    public let path: PathBytes
    public let kind: EntryKind
}

public struct SkippedItem: Equatable, Sendable {
    public let path: PathBytes
    public let reason: SkipReason
}

public struct WalkResult: Sendable {
    /// 이름 변환 대상. **자식이 부모보다 먼저** 온다.
    public let items: [WalkItem]
    /// 의도적으로 제외한 항목. 사용자에게 보고한다.
    public let skipped: [SkippedItem]
}

/// 디렉터리 트리를 bottom-up 으로 순회한다.
public enum TreeWalker {

    public static func collect(from roots: [PathBytes]) -> WalkResult {
        var items: [WalkItem] = []
        var skipped: [SkippedItem] = []
        for root in roots {
            visit(root, items: &items, skipped: &skipped, isRoot: true)
        }
        return WalkResult(items: items, skipped: skipped)
    }

    private static func visit(_ path: PathBytes,
                              items: inout [WalkItem],
                              skipped: inout [SkippedItem],
                              isRoot: Bool) {
        let name = path.lastComponent

        // 숨김 항목은 이름 변환도 재귀도 하지 않는다.
        // .git 내부를 건드리면 저장소가 깨진다.
        // 사용자가 직접 드롭한 최상위 항목은 예외로 처리한다.
        if !isRoot, name.first == UInt8(ascii: ".") {
            skipped.append(SkippedItem(path: path, reason: .hidden))
            return
        }

        guard let status = lstatus(of: path) else { return }
        let mode = status.st_mode & S_IFMT

        // 심볼릭 링크는 자신의 이름만 대상이고 따라가지 않는다.
        if mode == S_IFLNK {
            skipped.append(SkippedItem(path: path, reason: .symlink))
            items.append(WalkItem(path: path, kind: .symlink))
            return
        }

        guard mode == S_IFDIR else {
            items.append(WalkItem(path: path, kind: .file))
            return
        }

        // 번들 패키지는 이름만 바꾸고 내부로 들어가지 않는다.
        if isPackage(path) {
            skipped.append(SkippedItem(path: path, reason: .bundle))
            items.append(WalkItem(path: path, kind: .directory))
            return
        }

        // 자식을 먼저 처리한다. 접근 실패는 해당 디렉터리만 건너뛴다.
        if let entries = try? DirectoryLister.entries(in: path) {
            for entry in entries {
                visit(path.appending(entry.name), items: &items, skipped: &skipped, isRoot: false)
            }
        }

        // 부모는 자식보다 나중에 넣는다. 이 순서가 깨지면 자식 경로가 무효가 된다.
        items.append(WalkItem(path: path, kind: .directory))
    }

    /// `.app` · `.rtfd` · `.photoslibrary` 등 Finder 가 하나의 문서처럼 다루는 디렉터리인가.
    ///
    /// `UTType(filenameExtension:)` 은 쓸 수 없다. `.app` 이 `com.apple.application-file`
    /// 로 해석되어 `.package` 에 conform 하지 않고, `.rtfd` 는 미등록 동적 타입이 된다.
    /// 이 조회는 읽기 전용이라 Foundation 을 써도 NFD 변환 문제가 없다.
    private static func isPackage(_ path: PathBytes) -> Bool {
        guard let string = path.utf8String else { return false }
        let url = URL(fileURLWithPath: string)
        return (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }

    private static func lstatus(of path: PathBytes) -> stat? {
        var status = stat()
        guard path.withCString({ lstat($0, &status) }) == 0 else { return nil }
        return status
    }
}
