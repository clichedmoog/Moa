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

public enum WalkFailureReason: Equatable, Sendable {
    /// 디렉터리를 읽지 못했다. 안쪽 항목을 하나도 보지 못했다.
    case unreadableDirectory
    /// 항목 자체에 접근하지 못했다. 사라졌거나 권한이 없다.
    case inaccessible
}

public struct WalkFailure: Equatable, Sendable {
    public let path: PathBytes
    public let reason: WalkFailureReason
    public let errno: Int32
}

public struct WalkResult: Sendable {
    /// 이름 변환 대상. **자식이 부모보다 먼저** 온다.
    public let items: [WalkItem]
    /// 의도적으로 제외한 항목. 사용자에게 보고한다.
    public let skipped: [SkippedItem]
    /// 의도치 않게 보지 못한 항목. `skipped` 와 절대 섞이면 안 된다 —
    /// 이건 "제외했다" 가 아니라 "확인하지 못했다" 는 뜻이다.
    public let failures: [WalkFailure]
}

/// 디렉터리 트리를 bottom-up 으로 순회한다.
public enum TreeWalker {

    public static func collect(from roots: [PathBytes]) -> WalkResult {
        var items: [WalkItem] = []
        var skipped: [SkippedItem] = []
        var failures: [WalkFailure] = []
        for root in roots {
            visit(root, items: &items, skipped: &skipped, failures: &failures, isRoot: true)
        }
        return WalkResult(items: items, skipped: skipped, failures: failures)
    }

    private static func visit(_ path: PathBytes,
                              items: inout [WalkItem],
                              skipped: inout [SkippedItem],
                              failures: inout [WalkFailure],
                              isRoot: Bool) {
        let name = path.lastComponent

        // 숨김 항목은 이름 변환도 재귀도 하지 않는다.
        // .git 내부를 건드리면 저장소가 깨진다.
        // 사용자가 직접 드롭한 최상위 항목은 예외로 처리한다.
        if !isRoot, name.first == UInt8(ascii: ".") {
            skipped.append(SkippedItem(path: path, reason: .hidden))
            return
        }

        let statusResult = lstatus(of: path)
        guard let status = statusResult.status else {
            // 사라졌거나 권한이 없다. "제외했다" 가 아니라 "확인하지 못했다" — skipped 와
            // 섞이면 안 된다.
            failures.append(WalkFailure(path: path, reason: .inaccessible, errno: statusResult.errno))
            return
        }
        let mode = status.st_mode & S_IFMT

        // 심볼릭 링크는 자신의 이름만 대상이고 따라가지 않는다.
        if mode == S_IFLNK {
            skipped.append(SkippedItem(path: path, reason: .symlink))
            items.append(WalkItem(path: path, kind: .symlink))
            return
        }

        guard mode == S_IFDIR else {
            // 일반 파일이 아닌 특수 파일(소켓·FIFO·디바이스 노드)은 DirectoryLister 와
            // 동일하게 `.other` 로 분류한다. rename(2) 은 파일 종류를 가리지 않으므로
            // 이름 변환 대상에서는 제외하지 않는다.
            let kind: EntryKind = mode == S_IFREG ? .file : .other
            items.append(WalkItem(path: path, kind: kind))
            return
        }

        // 번들 패키지는 이름만 바꾸고 내부로 들어가지 않는다.
        if isPackage(path) {
            skipped.append(SkippedItem(path: path, reason: .bundle))
            items.append(WalkItem(path: path, kind: .directory))
            return
        }

        // 자식을 먼저 처리한다. 디렉터리를 읽지 못하면 그 사실을 failures 에 남긴다 —
        // 빈 디렉터리처럼 조용히 지나치면 안 쪽에 남은 NFD 이름을 "처리했다" 고
        // 잘못 보고하는 셈이 된다. 디렉터리 자신은 여전히 이름 변환 대상이다.
        do {
            let entries = try DirectoryLister.entries(in: path)
            for entry in entries {
                visit(path.appending(entry.name), items: &items, skipped: &skipped, failures: &failures, isRoot: false)
            }
        } catch DirectoryListerError.cannotOpen(let errno) {
            failures.append(WalkFailure(path: path, reason: .unreadableDirectory, errno: errno))
        } catch DirectoryListerError.readFailed(let errno) {
            failures.append(WalkFailure(path: path, reason: .unreadableDirectory, errno: errno))
        } catch {
            failures.append(WalkFailure(path: path, reason: .unreadableDirectory, errno: 0))
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

    /// `errno` 는 실패 시점에 곧바로 함께 담아 돌려준다. 호출부가 나중에 전역 `errno` 를
    /// 읽으면 그 사이에 다른 호출이 값을 덮어썼을 위험이 있다.
    private static func lstatus(of path: PathBytes) -> (status: stat?, errno: Int32) {
        var status = stat()
        guard path.withCString({ lstat($0, &status) }) == 0 else { return (nil, errno) }
        return (status, 0)
    }
}
