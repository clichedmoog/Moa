import Foundation

public enum ArchivePlacementError: Error, Equatable {
    case cannotPlace(errno: Int32)
}

/// 만들어진 아카이브를 최종 위치에 놓는다.
///
/// 아카이브는 항상 임시 파일에 만든 뒤 이 타입으로 옮긴다. 목적지에 직접 쓰지 않는 이유:
/// 사용자가 저장 패널에서 원본과 같은 이름을 고를 수 있고(읽는 중인 파일에 쓰면 깨진다),
/// 목적지가 압축 대상 트리 안일 수 있으며(자기 자신을 포함하려 든다),
/// 중간에 실패하면 목적지에 반쯤 쓰인 파일이 남는다.
public enum ArchivePlacement {

    /// 앱 컨테이너 안의 임시 경로. 이름이 ASCII 라 정규화 문제가 없다.
    public static func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moa-\(UUID().uuidString).zip")
    }

    /// 임시 파일을 목적지로 옮긴다. **목적지 이름은 NFC 로 쓴다.**
    ///
    /// Foundation 의 파일 생성 API 는 파일명을 NFD 로 쓴다(실측). 자소분리를 고치는 앱이
    /// 자소분리된 파일명을 만들지 않도록, 최종 배치는 POSIX `rename(2)` 에 NFC 바이트를 넘긴다.
    /// 마지막 경로 요소만 정규화하고 상위 경로 바이트는 그대로 둔다 — 상위 디렉터리는
    /// 이미 디스크에 존재하며 그 형태를 우리가 바꿀 이유가 없다.
    public static func place(temporary: URL, at destination: URL) throws {
        let target = normalizedDestination(destination)

        let renamed = PathBytes(Array(temporary.path.utf8)).withCString { source in
            target.withCString { dest in rename(source, dest) }
        }
        if renamed == 0 { return }

        // 다른 볼륨이면 rename(2) 이 EXDEV 로 실패한다. 복사로 대체한다.
        guard errno == EXDEV else { throw ArchivePlacementError.cannotPlace(errno: errno) }
        try copyAcrossVolumes(from: temporary, to: target)
    }

    /// 마지막 경로 요소만 NFC 로 바꾼 목적지.
    private static func normalizedDestination(_ destination: URL) -> PathBytes {
        let path = PathBytes(Array(destination.path.utf8))
        let parent = path.removingLastComponent()
        return parent.appending(Normalizer.normalized(path.lastComponent))
    }

    private static func copyAcrossVolumes(from temporary: URL, to target: PathBytes) throws {
        let data = try Data(contentsOf: temporary)
        let fd = target.withCString { open($0, O_CREAT | O_WRONLY | O_TRUNC, 0o644) }
        guard fd >= 0 else { throw ArchivePlacementError.cannotPlace(errno: errno) }
        defer { close(fd) }

        var written = 0
        while written < data.count {
            let count = data.withUnsafeBytes { raw -> Int in
                write(fd, raw.baseAddress!.advanced(by: written), data.count - written)
            }
            guard count > 0 else { throw ArchivePlacementError.cannotPlace(errno: errno) }
            written += count
        }
        _ = temporary.withUnsafeFileSystemRepresentation { unlink($0!) }
    }
}
