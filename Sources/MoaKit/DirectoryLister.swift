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
        while let pointer = readdir(handle) {
            var record = pointer.pointee
            let name = withUnsafeBytes(of: &record.d_name) { raw -> [UInt8] in
                let base = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                return Array(UnsafeBufferPointer(start: base, count: Int(record.d_namlen)))
            }
            if name == [0x2E] || name == [0x2E, 0x2E] { continue }
            result.append(DirectoryEntry(name: name, kind: kind(of: record, in: dir, name: name)))
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
            var status = stat()
            let path = dir.appending(name)
            guard path.withCString({ lstat($0, &status) }) == 0 else { return .other }
            switch status.st_mode & S_IFMT {
            case S_IFREG: return .file
            case S_IFDIR: return .directory
            case S_IFLNK: return .symlink
            default: return .other
            }
        }
    }
}
