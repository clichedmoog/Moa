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
        let currentStatus: stat
        switch lstatus(of: path) {
        case .success(let status):
            currentStatus = status
        case .failure(let code):
            return .failed(errno: code)
        }

        guard Normalizer.needsNormalization(oldName) else { return .alreadyNormalized }

        let parent = path.removingLastComponent()
        let newName = Normalizer.normalized(oldName)
        let destination = parent.appending(newName)

        // 충돌 검사. 대상이 존재하되 원본과 다른 파일이면 덮어쓰지 않는다.
        switch lstatus(of: destination) {
        case .success(let destinationStatus):
            // APFS(케이스 구분 여부 무관), HFS+, exFAT 는 모두 정규화 비민감
            // (normalization-insensitive) 이어서 NFD 이름과 NFC 이름이 항상 같은 파일
            // (같은 st_dev/st_ino) 을 가리킨다. 케이스 구분 APFS 이미지에서 실측해도
            // 마찬가지였다 — `!isSameFile` 은 세 볼륨 전부에서 도달 불가능하다.
            // 그래도 지우지 않는 이유는, 정규화에 민감한 네트워크 볼륨(SMB, NFS 등)에서는
            // NFD 이름과 NFC 이름이 서로 다른 두 파일일 수 있기 때문이다 — 죽은 코드가
            // 아니라 그런 볼륨을 위한 방어 코드다.
            let isSameFile = destinationStatus.st_dev == currentStatus.st_dev
                && destinationStatus.st_ino == currentStatus.st_ino
            if !isSameFile { return .skippedCollision }
        case .failure(let code) where code == ENOENT:
            break // 목적지 이름이 아예 없다 — 충돌이 아니다. 진행한다.
        case .failure(let code):
            // ENOENT 이외의 실패(EACCES, ENOTDIR, ELOOP 등)는 "충돌 없음"으로 조용히
            // 넘기지 않는다. 원인을 알 수 없는 채로 rename 을 시도하는 대신 명시적으로
            // 실패를 보고한다.
            return .failed(errno: code)
        }

        // 여기와 실제 rename(2) 호출 사이에는 알려진 시간차(TOCTOU) 창이 있다. 이 검사
        // 이후, rename 이전에 다른 프로세스가 목적지 이름으로 진짜 다른 파일을 만들면
        // 그 파일은 안전하게 건너뛰어지지 않고 rename(2) 에 덮여 사라진다. 이는 알려진
        // 채로 받아들인 한계다.
        //
        // 원자적으로 만드는 명백한 방법은 `renamex_np(..., RENAME_EXCL)` 이지만 쓰지
        // 않는다. 실측 결과 exFAT 에서 ENOTSUP 을 반환해 이 앱이 대상으로 하는 볼륨
        // 전체에 이식되지 않는다. (정규화 비민감 볼륨에서는 목적지 이름이 항상 "존재"
        // 하니 매 정상 rename 마다 RENAME_EXCL 이 헛되이 실패할 거라는 추측도 있었지만,
        // APFS 실측에서는 같은 inode 케이스에 대해 0 을 반환했다 — 진짜 이유는 exFAT 의
        // ENOTSUP 뿐이다.)
        var renameErrno: Int32 = 0
        let result: Int32 = path.withCString { source in
            destination.withCString { target -> Int32 in
                let outcome = rename(source, target)
                renameErrno = errno
                return outcome
            }
        }
        guard result == 0 else { return .failed(errno: renameErrno) }

        // 디스크에 실제로 반영됐는지 확인한다.
        // 여기가 조용한 실패와 NFD 강제 볼륨을 모두 잡아내는 지점이다.
        guard let actual = NameVerifier.onDiskName(of: destination), actual == newName else {
            return .verificationFailed
        }
        return .renamed
    }

    /// `lstat` 결과. 실패 시 errno 를 함께 담아 호출부가 원인을 판단할 수 있게 한다.
    private enum LstatResult {
        case success(stat)
        case failure(errno: Int32)
    }

    /// `path.withCString` 이 반환하면 임시 C 문자열 버퍼가 해제된다. 그 해제(큰 버퍼의
    /// free/munmap 등)가 전역 `errno` 를 보존한다는 보장은 POSIX 에 없다. 그래서 errno 는
    /// 반드시 클로저 안, 시스템 호출 직후에 캡처해야 한다 — 클로저를 빠져나온 뒤 전역
    /// errno 를 읽으면 안 된다. `DirectoryLister` 와 같은 원칙이다.
    private static func lstatus(of path: PathBytes) -> LstatResult {
        var status = stat()
        var capturedErrno: Int32 = 0
        let result = path.withCString { pointer -> Int32 in
            let outcome = lstat(pointer, &status)
            capturedErrno = errno
            return outcome
        }
        guard result == 0 else { return .failure(errno: capturedErrno) }
        return .success(status)
    }
}
