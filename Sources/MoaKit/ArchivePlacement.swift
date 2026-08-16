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

    /// 다른 볼륨으로의 복사. `rename(2)` 이 `EXDEV` 로 실패했을 때만 호출된다.
    ///
    /// 불변식: **`open` 에 성공해 목적지를 실제로 손댄 뒤의 실패만 정리한다. `open`
    /// 이전에 존재하던, 우리가 성공적으로 열지 못한 목적지는 절대 지우지 않는다.**
    ///
    /// `open` 은 목적지 파일 자신의 권한이 아니라 담고 있는 디렉터리의 쓰기 권한만
    /// 본다 — 그래서 이미 존재하는, 읽기 전용으로 `chmod` 된 목적지 파일에 대해
    /// `open` 이 실패할 수 있다. 그 경우 아무것도 쓰지 않았으니 원래 파일이 그대로
    /// 남아 있다. 여기서 `unlink` 를 하면 우리가 한 byte 도 쓰지 않은 사용자의 기존
    /// 파일을 지우는 셈이 된다 — 손상된 zip 을 남기는 것보다 더 나쁘다: 손상된
    /// 파일은 적어도 실패했다는 증거가 남지만, 조용히 지워진 원본은 복구할 수 없다.
    /// `open` 이 성공하면 그 순간부터 목적지는 이미 `O_TRUNC` 로 비워진, 우리 것이 된
    /// 파일이다 — 그 뒤의 실패(`write` 실패, 짧은 write 등)는 안전하게 정리해도 된다.
    ///
    /// 남는 틈: `open` 성공 뒤의 `unlink` 자체가 크래시나 정전으로 실행되지 못하면
    /// 잘린 파일이 남는다. 같은 볼륨에 임시 파일을 만들고 `rename` 으로 교체하는
    /// 편(rename 은 원자적이라 이 문제가 아예 없다)이 더 나은 해법이지만, 샌드박스에서는
    /// 사용자가 저장 패널로 고른 항목의 **상위 디렉터리**에 대한 쓰기 권한이 보통
    /// 주어지지 않는다(실측: `EPERM`) — 그래서 형제 임시 파일을 안정적으로 만들 수
    /// 없다. 저장 패널의 권한 부여 범위가 상위 디렉터리까지 포함하는 것으로 확인되면
    /// 다시 검토할 만하다.
    private static func copyAcrossVolumes(from temporary: URL, to target: PathBytes) throws {
        let data = try Data(contentsOf: temporary)

        // 여기서 실패하면(권한 부족 등) 목적지를 아직 전혀 건드리지 않았다 — 지울
        // 것이 없다. do/catch 밖에 두어 아래 catch 의 unlink 가 이 실패에는 절대
        // 반응하지 않게 한다.
        let fd = target.withCString { open($0, O_CREAT | O_WRONLY | O_TRUNC, 0o644) }
        guard fd >= 0 else { throw ArchivePlacementError.cannotPlace(errno: errno) }
        defer { close(fd) }

        do {
            var written = 0
            while written < data.count {
                let count = data.withUnsafeBytes { raw -> Int in
                    write(fd, raw.baseAddress!.advanced(by: written), data.count - written)
                }
                if count < 0 {
                    throw ArchivePlacementError.cannotPlace(errno: errno)
                }
                guard count > 0 else {
                    // POSIX 는 count == 0 일 때 errno 를 보장하지 않는다 — 이전 호출의
                    // 오래된 errno 를 잘못 읽지 않도록 고정된 값을 쓴다. 일반 파일
                    // 에서는 애초에 일어나지 않아야 하는 상황이다.
                    throw ArchivePlacementError.cannotPlace(errno: EIO)
                }
                written += count
            }
        } catch {
            // open 이 이미 성공했다 — O_TRUNC 로 기존 내용을 지운 뒤이므로 목적지는
            // 이제 우리 책임이다. 손상된 채로 남기지 않는다. unlink 자체의 성공
            // 여부는 따지지 않는다: 이미 원래 에러를 던지는 중이므로 정리 실패로
            // 그걸 덮으면 안 된다.
            _ = target.withCString { unlink($0) }
            throw error
        }
        _ = temporary.withUnsafeFileSystemRepresentation { unlink($0!) }
    }
}
