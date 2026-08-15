import Foundation

/// 디스크에 실제로 저장된 이름을 조회한다.
///
/// rename 이 실제로 반영됐는지 확인하는 유일한 방법이다.
/// `FileManager.moveItem` 은 아무것도 바꾸지 않고도 성공을 반환하며,
/// HFS+ / exFAT 볼륨은 NFC 로 쓴 이름을 NFD 로 되돌린다.
/// `getattrlist(ATTR_CMN_NAME)` 은 디렉터리 전체를 훑지 않고 O(1) 로 답을 준다.
public enum NameVerifier {

    private static let defaultBufferSize = 2048

    public static func onDiskName(of path: PathBytes) -> [UInt8]? {
        onDiskName(of: path, initialBufferSize: defaultBufferSize)
    }

    /// 테스트에서 초기 버퍼를 일부러 작게 줘서 재시도 경로를 강제로 태우기 위한 시임(seam).
    /// 실서비스 호출은 `onDiskName(of:)` 을 통해 기본 버퍼 크기(2048)를 쓴다.
    static func onDiskName(of path: PathBytes, initialBufferSize: Int) -> [UInt8]? {
        switch attempt(path: path, bufferSize: initialBufferSize) {
        case .success(let bytes):
            return bytes
        case .failure:
            return nil
        case .tooSmall(let requiredSize):
            // 버퍼가 모자랐던 만큼만 정확히 키워서 딱 한 번만 재시도한다 — 무한 루프에 빠지지 않는다.
            guard case .success(let bytes) = attempt(path: path, bufferSize: requiredSize) else {
                return nil
            }
            return bytes
        }
    }

    private enum Attempt {
        case success([UInt8])
        case tooSmall(requiredSize: Int)
        case failure
    }

    private static func attempt(path: PathBytes, bufferSize: Int) -> Attempt {
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_NAME)

        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let status = path.withCString { pathPointer in
            buffer.withUnsafeMutableBytes { raw in
                getattrlist(pathPointer, &attributes, raw.baseAddress, raw.count,
                            UInt32(FSOPT_NOFOLLOW))
            }
        }
        guard status == 0 else { return .failure }

        return buffer.withUnsafeBytes { raw -> Attempt in
            guard let base = raw.baseAddress else { return .failure }
            // 버퍼 선두 4바이트는 전체 길이. 그 뒤가 attrreference_t 다.
            let reference = base.advanced(by: 4)
                .assumingMemoryBound(to: attrreference_t.self).pointee
            let length = Int(reference.attr_length)
            guard length > 1 else { return .failure }
            // 버퍼가 너무 작아도 getattrlist 는 ERANGE 를 돌려주지 않고 status == 0 과 함께
            // attr_length·attr_dataoffset 에 "실제" 값을 채워 넣는다 — 잘린 값이 아니다.
            // 그래서 슬라이싱하기 전에 이 값들이 버퍼 안에 실제로 들어오는지 반드시 확인해야 한다.
            // 확인 없이 바로 슬라이싱하면 버퍼 밖의 힙 메모리를 읽는다.
            let requiredSize = 4 + Int(reference.attr_dataoffset) + length
            guard requiredSize <= buffer.count else {
                return .tooSmall(requiredSize: requiredSize)
            }
            let start = base.advanced(by: 4 + Int(reference.attr_dataoffset))
                .assumingMemoryBound(to: UInt8.self)
            // attr_length 는 NUL 을 포함하므로 1을 뺀다.
            return .success(Array(UnsafeBufferPointer(start: start, count: length - 1)))
        }
    }
}
