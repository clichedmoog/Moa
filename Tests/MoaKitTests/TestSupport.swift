import Foundation
@testable import MoaKit

/// 테스트 픽스처를 **원시 POSIX 호출로** 만든다.
///
/// `FileManager.createFile` 을 쓰면 안 되는 이유는 Foundation 이 경로를 NFD 로 바꾸기 때문이다.
/// NFC 이름의 픽스처를 만들 방법이 없어진다.
enum TestSupport {

    static func nfd(_ s: String) -> [UInt8] {
        Array(s.decomposedStringWithCanonicalMapping.utf8)
    }

    static func nfc(_ s: String) -> [UInt8] {
        Array(s.precomposedStringWithCanonicalMapping.utf8)
    }

    static func makeTempDir(function: String = #function) -> PathBytes {
        let unique = "moa-test-\(function.hashValue.magnitude)-\(getpid())"
        let path = PathBytes(NSTemporaryDirectory()).appending(Array(unique.utf8))
        remove(path)
        _ = path.withCString { mkdir($0, 0o755) }
        return path
    }

    @discardableResult
    static func makeFile(named name: [UInt8], in dir: PathBytes, contents: String = "x") -> PathBytes {
        let full = dir.appending(name)
        let fd = full.withCString { open($0, O_CREAT | O_WRONLY | O_TRUNC, 0o644) }
        precondition(fd >= 0, "픽스처 파일 생성 실패: errno=\(errno)")
        let data = Array(contents.utf8)
        _ = data.withUnsafeBufferPointer { write(fd, $0.baseAddress, data.count) }
        close(fd)
        return full
    }

    @discardableResult
    static func makeDir(named name: [UInt8], in dir: PathBytes) -> PathBytes {
        let full = dir.appending(name)
        let result = full.withCString { mkdir($0, 0o755) }
        precondition(result == 0, "픽스처 디렉터리 생성 실패: errno=\(errno)")
        return full
    }

    @discardableResult
    static func makeSymlink(named name: [UInt8], to target: PathBytes, in dir: PathBytes) -> PathBytes {
        let full = dir.appending(name)
        let result = target.withCString { targetPtr in
            full.withCString { linkPtr in symlink(targetPtr, linkPtr) }
        }
        precondition(result == 0, "픽스처 심볼릭 링크 생성 실패: errno=\(errno)")
        return full
    }

    /// `readdir` 로 디스크에 저장된 원시 이름을 읽는다. 테스트의 유일한 성공 판정 근거다.
    static func rawNames(in dir: PathBytes) -> [[UInt8]] {
        guard let handle = dir.withCString({ opendir($0) }) else { return [] }
        defer { closedir(handle) }
        var names: [[UInt8]] = []
        while let entry = readdir(handle) {
            var record = entry.pointee
            let name = withUnsafeBytes(of: &record.d_name) { raw -> [UInt8] in
                let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                return Array(UnsafeBufferPointer(start: base, count: Int(record.d_namlen)))
            }
            if name == [0x2E] || name == [0x2E, 0x2E] { continue }
            names.append(name)
        }
        return names.sorted { $0.lexicographicallyPrecedes($1) }
    }

    static func remove(_ path: PathBytes) {
        guard let string = path.utf8String else { return }
        try? FileManager.default.removeItem(atPath: string)
    }
}
