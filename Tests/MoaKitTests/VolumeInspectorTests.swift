import XCTest
@testable import MoaKit

final class VolumeInspectorTests: XCTestCase {

    func testDetectsAPFSOnTempDir() throws {
        let dir = TestSupport.makeTempDir()
        defer { TestSupport.remove(dir) }

        let info = try XCTUnwrap(VolumeInspector.inspect(dir))
        XCTAssertEqual(info.fileSystemName, "apfs")
        XCTAssertTrue(info.preservesNormalization)
    }

    func testReturnsNilForMissingPath() {
        XCTAssertNil(VolumeInspector.inspect(PathBytes("/이런경로는없다/절대로")))
    }

    func testKnownNFDForcingFileSystems() {
        for name in ["hfs", "exfat", "msdos", "smbfs"] {
            XCTAssertFalse(VolumeInspector.preservesNormalization(fileSystemName: name),
                           "\(name) 은 NFD 를 강제한다")
        }
    }

    func testAPFSPreservesNormalization() {
        XCTAssertTrue(VolumeInspector.preservesNormalization(fileSystemName: "apfs"))
    }

    /// 모르는 파일시스템은 낙관적으로 본다.
    /// 실제 판정은 Renamer 의 사후 검증이 하므로 여기서 막을 필요가 없다.
    func testUnknownFileSystemIsAssumedPreserving() {
        XCTAssertTrue(VolumeInspector.preservesNormalization(fileSystemName: "someexoticfs"))
    }

    // MARK: - F5 회귀: decodeFixedCString 이 배열 경계 밖을 읽지 않는다

    /// 평범한 NUL 종료 케이스 — 기존 동작과 다르지 않아야 한다.
    func testDecodeFixedCStringStopsAtNUL() {
        var bytes = Array("apfs".utf8)
        bytes += Array(repeating: 0, count: 16 - bytes.count)
        XCTAssertEqual(VolumeInspector.decodeFixedCString(bytes), "apfs")
    }

    /// 배열 16바이트가 전부 non-NUL 이면, `String(cString:)` 이었다면 배열 밖
    /// 인접 메모리까지 읽어 이름이 16자보다 길어졌을 것이다. 고친 구현은 종료자가
    /// 없어도 배열 크기(count)에서 멈춰야 한다 — 정확히 16자, 더도 덜도 아니다.
    func testDecodeFixedCStringBoundsReadWhenNoNULPresent() {
        let bytes = Array(repeating: UInt8(ascii: "a"), count: 16)
        let name = VolumeInspector.decodeFixedCString(bytes)
        XCTAssertEqual(name, String(repeating: "a", count: 16))
        XCTAssertEqual(name.utf8.count, 16, "배열 경계를 넘어 추가로 읽으면 안 된다")
    }

    /// 빈 배열이어도 안전하게 빈 문자열을 돌려줘야 한다(baseAddress 가 nil 인 경계 케이스).
    func testDecodeFixedCStringHandlesEmptyArray() {
        XCTAssertEqual(VolumeInspector.decodeFixedCString([]), "")
    }
}
