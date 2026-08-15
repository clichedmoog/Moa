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

        let name = withUnsafeBytes(of: &buffer.f_fstypename) { raw -> String in
            let base = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: base)
        }
        return VolumeInfo(fileSystemName: name,
                          preservesNormalization: preservesNormalization(fileSystemName: name))
    }

    /// 모르는 파일시스템은 보존하는 쪽으로 가정한다.
    /// 최종 판정은 `Renamer` 의 사후 검증이 하므로 여기서 미리 막을 이유가 없다.
    public static func preservesNormalization(fileSystemName: String) -> Bool {
        !nfdForcing.contains(fileSystemName.lowercased())
    }
}
