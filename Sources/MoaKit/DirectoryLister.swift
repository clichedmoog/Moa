import Foundation

public enum EntryKind: Equatable, Sendable {
    case file
    case directory
    case symlink
    case other
}

public struct DirectoryEntry: Equatable, Sendable {
    public let name: [UInt8]
    public let kind: EntryKind

    public init(name: [UInt8], kind: EntryKind) {
        self.name = name
        self.kind = kind
    }
}

public enum DirectoryListerError: Error, Equatable {
    case cannotOpen(errno: Int32)
    case readFailed(errno: Int32)
}

/// `readdir(3)` 으로 디렉터리를 읽는다.
///
/// Foundation 의 `contentsOfDirectory` 대신 쓰는 이유는 디스크 원시 바이트를 확실히 얻기 위해서다.
/// Foundation 은 AppleDouble(`._*`) 같은 항목을 걸러내기도 하는데, 우리는 그것까지 봐야 한다.
public enum DirectoryLister {

    public static func entries(in dir: PathBytes) throws -> [DirectoryEntry] {
        guard let handle = dir.withCString({ opendir($0) }) else {
            throw DirectoryListerError.cannotOpen(errno: errno)
        }
        defer { closedir(handle) }

        var result: [DirectoryEntry] = []
        // readdir 은 디렉터리 끝에 도달했을 때도, 읽기 오류(예: 이동식·네트워크 볼륨의
        // I/O 오류)가 났을 때도 똑같이 NULL 을 돌려준다. POSIX 관용구대로 호출 전에
        // errno 를 0으로 비우고 루프가 끝난 뒤 확인해야 둘을 구분할 수 있다.
        errno = 0
        while let pointer = readdir(handle) {
            var record = pointer.pointee
            let name = withUnsafeBytes(of: &record.d_name) { raw -> [UInt8] in
                let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                return Array(UnsafeBufferPointer(start: base, count: Int(record.d_namlen)))
            }
            if name != [0x2E] && name != [0x2E, 0x2E] {
                result.append(DirectoryEntry(name: name, kind: kind(of: record, in: dir, name: name)))
            }
            // kind(of:) 는 DT_UNKNOWN 일 때 lstat 을 호출하는데, 그 호출이 실패하면 errno 가
            // 오염된다. 다음 readdir 호출 전에 다시 비워서 거짓 오류 판정을 막는다.
            errno = 0
        }
        if errno != 0 {
            throw DirectoryListerError.readFailed(errno: errno)
        }
        return result
    }

    private static func kind(of record: dirent, in dir: PathBytes, name: [UInt8]) -> EntryKind {
        switch Int32(record.d_type) {
        case Int32(DT_REG): return .file
        case Int32(DT_DIR): return .directory
        case Int32(DT_LNK): return .symlink
        default:
            // 일부 파일시스템은 DT_UNKNOWN 을 돌려준다. lstat 으로 확인한다.
            return classifyViaLstat(dir.appending(name))
        }
    }

    /// `lstat` 만으로 항목 종류를 판정한다. `DT_UNKNOWN` 폴백이 쓰는 로직을, 실제
    /// 파일시스템에서 `DT_UNKNOWN` 을 강제하지 않고도 독립적으로 테스트하기 위해 분리했다.
    static func classifyViaLstat(_ path: PathBytes) -> EntryKind {
        var status = stat()
        guard path.withCString({ lstat($0, &status) }) == 0 else { return .other }
        switch status.st_mode & S_IFMT {
        case S_IFREG: return .file
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }
}
