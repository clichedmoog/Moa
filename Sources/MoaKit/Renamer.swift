import Foundation

public enum RenameOutcome: Equatable, Sendable {
    /// 이름을 바꾸고 디스크에서 NFC 임을 확인했다.
    case renamed
    /// 이미 NFC 라 건드리지 않았다. 수정 시각이 보존된다.
    case alreadyNormalized
    /// 대상 이름으로 다른 파일이 이미 존재한다. 덮어쓰지 않고 건너뛰었다.
    case skippedCollision
    /// rename 은 성공했으나 디스크가 NFC 가 아니다. HFS+ / exFAT 볼륨이다.
    case verificationFailed
    /// 시스템 호출이 실패했다.
    case failed(errno: Int32)
}

/// 파일명을 NFC 로 바꾼다.
///
/// `FileManager.moveItem` 을 쓰지 않는다. Foundation 은 경로를 커널에 넘기기 전에 NFD 로
/// 변환하므로 "NFD → NFD" rename 이 되어 **에러 없이 아무 일도 일어나지 않는다.**
public enum Renamer {

    public static func normalizeName(at path: PathBytes) -> RenameOutcome {
        let oldName = path.lastComponent
        guard !oldName.isEmpty else { return .failed(errno: EINVAL) }

        // 원본이 실제로 존재하는지 먼저 확인한다.
        guard let currentStatus = lstatus(of: path) else {
            return .failed(errno: errno)
        }

        guard Normalizer.needsNormalization(oldName) else { return .alreadyNormalized }

        let parent = path.removingLastComponent()
        let newName = Normalizer.normalized(oldName)
        let destination = parent.appending(newName)

        // 충돌 검사. 대상이 존재하되 원본과 다른 파일이면 덮어쓰지 않는다.
        //
        // APFS / HFS+ / exFAT 는 정규화를 무시하고 이름을 비교하므로(normalization-insensitive)
        // NFD 이름과 NFC 이름은 같은 파일을 가리킨다. 그때는 (st_dev, st_ino) 가 일치한다.
        // 정규화에 민감한 볼륨(네트워크 등)에서만 진짜 충돌이 발생할 수 있다.
        if let destinationStatus = lstatus(of: destination) {
            let isSameFile = destinationStatus.st_dev == currentStatus.st_dev
                && destinationStatus.st_ino == currentStatus.st_ino
            if !isSameFile { return .skippedCollision }
        }

        let result = path.withCString { source in
            destination.withCString { target in
                rename(source, target)
            }
        }
        guard result == 0 else { return .failed(errno: errno) }

        // 디스크에 실제로 반영됐는지 확인한다.
        // 여기가 조용한 실패와 NFD 강제 볼륨을 모두 잡아내는 지점이다.
        guard let actual = NameVerifier.onDiskName(of: destination), actual == newName else {
            return .verificationFailed
        }
        return .renamed
    }

    private static func lstatus(of path: PathBytes) -> stat? {
        var status = stat()
        guard path.withCString({ lstat($0, &status) }) == 0 else { return nil }
        return status
    }
}
