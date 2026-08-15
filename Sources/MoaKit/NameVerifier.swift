import Foundation

/// 디스크에 실제로 저장된 이름을 조회한다.
///
/// rename 이 실제로 반영됐는지 확인하는 유일한 방법이다.
/// `FileManager.moveItem` 은 아무것도 바꾸지 않고도 성공을 반환하며,
/// HFS+ / exFAT 볼륨은 NFC 로 쓴 이름을 NFD 로 되돌린다.
/// `getattrlist(ATTR_CMN_NAME)` 은 디렉터리 전체를 훑지 않고 O(1) 로 답을 준다.
public enum NameVerifier {

    public static func onDiskName(of path: PathBytes) -> [UInt8]? {
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_NAME)

        var buffer = [UInt8](repeating: 0, count: 2048)
        let status = path.withCString { pathPointer in
            buffer.withUnsafeMutableBytes { raw in
                getattrlist(pathPointer, &attributes, raw.baseAddress, raw.count,
                            UInt32(FSOPT_NOFOLLOW))
            }
        }
        guard status == 0 else { return nil }

        return buffer.withUnsafeBytes { raw -> [UInt8]? in
            guard let base = raw.baseAddress else { return nil }
            // 버퍼 선두 4바이트는 전체 길이. 그 뒤가 attrreference_t 다.
            let reference = base.advanced(by: 4)
                .assumingMemoryBound(to: attrreference_t.self).pointee
            let length = Int(reference.attr_length)
            guard length > 1 else { return nil }
            let start = base.advanced(by: 4 + Int(reference.attr_dataoffset))
                .assumingMemoryBound(to: UInt8.self)
            // attr_length 는 NUL 을 포함하므로 1을 뺀다.
            return Array(UnsafeBufferPointer(start: start, count: length - 1))
        }
    }
}
