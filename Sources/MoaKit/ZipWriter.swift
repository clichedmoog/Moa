import Foundation
import ZIPFoundation

public struct ZipResult: Equatable, Sendable {
    public let entryCount: Int
    /// 맥 전용 파일 등 의도적으로 뺀 항목 수.
    public let excludedCount: Int
    /// 읽지 못해 아카이브에 넣지 못한 항목 수.
    /// 0 이 아니면 사용자에게 반드시 알린다 — 빠진 걸 모른 채 USB 로 옮기면 안 된다.
    public let failureCount: Int
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
        var excludedCount = 0
        var failureCount = 0

        for root in roots {
            let base = root.removingLastComponent()
            let walk = TreeWalker.collect(from: [root])

            // 아카이브는 위에서 아래로 읽는 편이 자연스러우므로 bottom-up 을 뒤집는다.
            for item in walk.items.reversed() {
                let name = item.path.lastComponent
                if ZipExclusions.shouldExclude(name: name) {
                    excludedCount += 1
                    continue
                }
                // 디렉터리 자체는 엔트리로 넣지 않는다. 파일 경로에 이미 포함된다.
                guard item.kind == .file else { continue }

                guard let relative = relativePath(of: item.path, from: base) else { continue }
                guard let sourcePath = item.path.utf8String else { continue }

                try archive.addEntry(with: relative,
                                     fileURL: URL(fileURLWithPath: sourcePath),
                                     compressionMethod: .deflate)
                entryCount += 1
            }

            excludedCount += walk.skipped.count
            // 읽지 못한 항목은 "제외"가 아니다. 아카이브에서 빠졌다는 사실을 사용자에게 알려야 한다.
            failureCount += walk.failures.count
        }

        try ArchivePlacement.place(temporary: temporary, at: destination)
        return ZipResult(entryCount: entryCount,
                         excludedCount: excludedCount,
                         failureCount: failureCount)
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
}
