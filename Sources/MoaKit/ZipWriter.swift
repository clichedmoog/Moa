import Foundation
import ZIPFoundation

public struct ZipResult: Sendable {
    public let entryCount: Int
    /// 의도적으로 넣지 않은 항목. 각각 이유를 담는다 — 맥 전용 파일, 심볼릭 링크,
    /// 번들 내용물, 특수 파일, 이름이 올바른 UTF-8 이 아닌 파일, 숨김 항목.
    public let omitted: [ReportEntry]
    /// 읽지 못해 넣지 못한 항목.
    /// 비어 있지 않으면 사용자에게 반드시 알린다 — 빠진 걸 모른 채 USB 로 옮기면 안 된다.
    public let failed: [ReportEntry]

    public var excludedCount: Int { omitted.count }
    public var failureCount: Int { failed.count }
}

/// NFC 이름과 UTF-8 플래그를 갖춘 ZIP 을 만든다.
///
/// 원본은 건드리지 않는다. 디스크 위 이름을 고칠 수 없는 볼륨(exFAT USB 등)에서도
/// ZIP 안의 이름은 우리가 정하므로 온전히 NFC 로 나간다.
public enum ZipWriter {

    public static func write(roots: [PathBytes], to destination: URL) throws -> ZipResult {
        // 목적지에 직접 쓰지 않는다. 임시 파일에 만든 뒤 마지막에 옮긴다.
        // 이유는 ArchivePlacement 의 주석 참조 — 자기 자신 덮어쓰기와 NFD 파일명을 동시에 막는다.
        let temporary = ArchivePlacement.makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: temporary) }

        let archive = try Archive(url: temporary, accessMode: .create)

        var entryCount = 0
        var omitted: [ReportEntry] = []
        var failed: [ReportEntry] = []

        for root in roots {
            let base = root.removingLastComponent()
            let walk = TreeWalker.collect(from: [root])

            // 아카이브는 위에서 아래로 읽는 편이 자연스러우므로 bottom-up 을 뒤집는다.
            for item in walk.items.reversed() {
                switch item.kind {
                case .directory:
                    // 디렉터리 자체는 엔트리로 넣지 않는다. 안의 파일 경로에 이미
                    // 포함되므로 "빠뜨렸다"고 볼 것도 없다 — omitted 에 올리지 않는다.
                    continue
                case .symlink:
                    // TreeWalker 는 심볼릭 링크를 items(kind: .symlink)와
                    // skipped(reason: .symlink) 양쪽에 올린다. 기록은 여기서 한 번만
                    // 한다 — skipped 루프에서는 .symlink 를 건너뛴다.
                    omitted.append(ReportEntry(path: item.path.displayString,
                                               detail: "심볼릭 링크 — 대상을 따라가지 않음"))
                    continue
                case .other:
                    // 소켓·FIFO·디바이스 노드. 파일로 읽을 수 없으니 시도조차 하지 않는다.
                    omitted.append(ReportEntry(path: item.path.displayString,
                                               detail: "특수 파일이라 포함할 수 없음"))
                    continue
                case .file:
                    break
                }

                guard let relative = relativePath(of: item.path, from: base) else { continue }

                // 루트 이름을 포함해 경로의 모든 구성 요소를 검사한다. 마지막 요소만
                // 보면 `__MACOSX/leaked.txt` 처럼 부모 디렉터리가 제외 대상이어도
                // 그 안의 파일이 그대로 살아남는다. ZipCleaner(Task 10)도 엔트리
                // 경로를 `/` 로 나눠 같은 방식으로 판정한다 — 이 판정을 그와 맞춘다.
                let components = relative.utf8.split(separator: UInt8(ascii: "/"),
                                                      omittingEmptySubsequences: true)
                if components.contains(where: { ZipExclusions.shouldExclude(name: Array($0)) }) {
                    omitted.append(ReportEntry(path: item.path.displayString,
                                               detail: "맥 전용 파일이라 제외함"))
                    continue
                }

                guard let sourcePath = item.path.utf8String else {
                    omitted.append(ReportEntry(path: item.path.displayString,
                                               detail: "파일명이 올바른 UTF-8 이 아니라 포함할 수 없음"))
                    continue
                }

                try archive.addEntry(with: relative,
                                     fileURL: URL(fileURLWithPath: sourcePath),
                                     compressionMethod: .deflate)
                entryCount += 1
            }

            for item in walk.skipped {
                switch item.reason {
                case .bundle:
                    omitted.append(ReportEntry(path: item.path.displayString,
                                               detail: "번들 — 내용물은 포함되지 않음"))
                case .hidden:
                    // 숨김 항목은 items 에 아예 오르지 않는다(TreeWalker 가 재귀도
                    // 하지 않는다) — 기록할 수 있는 곳이 여기뿐이다.
                    omitted.append(ReportEntry(path: item.path.displayString,
                                               detail: "숨김 항목이라 포함되지 않음"))
                case .symlink:
                    // 같은 경로가 items 에도 kind: .symlink 로 올라 위에서 이미
                    // 기록했다. 여기서 또 적으면 omitted 에 같은 경로가 두 번 남는다.
                    continue
                }
            }

            // 읽지 못한 항목은 "제외"가 아니다. 아카이브에서 빠졌다는 사실을 사용자에게 알려야 한다.
            for failure in walk.failures {
                switch failure.reason {
                case .unreadableDirectory:
                    failed.append(ReportEntry(path: failure.path.displayString,
                                              detail: "폴더를 읽지 못해 안쪽을 확인하지 못함 — \(message(for: failure.errno))"))
                case .inaccessible:
                    failed.append(ReportEntry(path: failure.path.displayString,
                                              detail: "항목에 접근하지 못함 — \(message(for: failure.errno))"))
                }
            }
        }

        try ArchivePlacement.place(temporary: temporary, at: destination)
        return ZipResult(entryCount: entryCount, omitted: omitted, failed: failed)
    }

    /// 아카이브 안에서 쓸 상대 경로를 NFC 로 만든다.
    private static func relativePath(of path: PathBytes, from base: PathBytes) -> String? {
        let full = path.bytes
        let prefix = base.bytes
        guard full.count > prefix.count, Array(full[..<prefix.count]) == prefix else {
            return path.utf8String.map { String(decoding: Normalizer.normalized(Array($0.utf8)), as: UTF8.self) }
        }
        var relative = Array(full[prefix.count...])
        if relative.first == UInt8(ascii: "/") { relative.removeFirst() }
        return String(decoding: Normalizer.normalized(relative), as: UTF8.self)
    }

    private static func message(for code: Int32) -> String {
        switch code {
        case EACCES, EPERM: return "권한이 없습니다"
        case ENOENT:        return "파일을 찾을 수 없습니다"
        case EROFS:         return "읽기 전용 볼륨입니다"
        default:            return "실패 (errno \(code))"
        }
    }
}
