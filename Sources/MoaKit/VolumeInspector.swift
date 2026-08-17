import Foundation

public struct VolumeInfo: Equatable, Sendable {
    public let fileSystemName: String
    /// 저장한 정규화 형태를 그대로 유지하는가.
    /// `false` 면 NFC 로 이름을 바꿔도 볼륨이 NFD 로 되돌린다.
    public let preservesNormalization: Bool
}

/// 대상 볼륨이 NFC 이름을 유지할 수 있는지 판별한다.
///
/// 실측 결과 APFS 만 정규화를 보존한다. HFS+ 는 물론이고 **exFAT 도** macOS 드라이버가
/// 이름을 NFD 로 되돌린다. exFAT USB 에 담긴 파일명은 맥에서 고칠 수 없으며,
/// 그런 경우의 해법은 이름 변환이 아니라 ZIP 생성이다.
public enum VolumeInspector {

    /// 이름을 NFD 로 강제해 변환이 무의미해지는 파일시스템.
    private static let nfdForcing: Set<String> = ["hfs", "exfat", "msdos", "ntfs", "smbfs", "cd9660"]

    public static func inspect(_ path: PathBytes) -> VolumeInfo? {
        var buffer = statfs()
        guard path.withCString({ statfs($0, &buffer) }) == 0 else { return nil }

        let bytes = withUnsafeBytes(of: &buffer.f_fstypename) { raw in Array(raw) }
        let name = decodeFixedCString(bytes)
        return VolumeInfo(fileSystemName: name,
                          preservesNormalization: preservesNormalization(fileSystemName: name))
    }

    /// f_fstypename 처럼 고정 크기 C 배열에 담긴, NUL 종료가 보장되지 않는 바이트를
    /// 안전하게 문자열로 디코드한다. `String(cString:)` 은 NUL 종료자를 찾을 때까지
    /// 읽으므로, 배열이 전부 non-NUL 이면 배열 경계를 넘어 인접 필드(f_fstypename 의
    /// 경우 f_mntonname)까지 읽는다. XNU 는 항상 strlcpy 로 NUL 종료를 보장하므로
    /// 실무에서는 도달 불가능하지만, `DirectoryLister`·`NameVerifier` 가 지키는
    /// "버퍼 밖을 읽지 않는다"는 규율을 여기서도 맞춘다 — strnlen 으로 배열 크기
    /// (`bytes.count`) 안에서만 종료자를 찾고, 없으면 배열 전체를 쓴다.
    /// 실제 `statfs` 호출과 분리된 내부 시임이라 인접 메모리 없이도 경계 동작을
    /// 테스트할 수 있다.
    static func decodeFixedCString(_ bytes: [UInt8]) -> String {
        let length = bytes.withUnsafeBufferPointer { buf -> Int in
            guard let base = buf.baseAddress else { return 0 }
            return base.withMemoryRebound(to: CChar.self, capacity: buf.count) { chars in
                strnlen(chars, buf.count)
            }
        }
        return String(decoding: bytes.prefix(length), as: UTF8.self)
    }

    /// 모르는 파일시스템은 보존하는 쪽으로 가정한다.
    /// 최종 판정은 `Renamer` 의 사후 검증이 하므로 여기서 미리 막을 이유가 없다.
    public static func preservesNormalization(fileSystemName: String) -> Bool {
        !nfdForcing.contains(fileSystemName.lowercased())
    }
}
