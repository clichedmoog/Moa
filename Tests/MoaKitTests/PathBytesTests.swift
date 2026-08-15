import XCTest
@testable import MoaKit

final class PathBytesTests: XCTestCase {

    func testAppendingJoinsWithSlash() {
        let base = PathBytes("/tmp/moa")
        let joined = base.appending(Array("파일.txt".utf8))
        XCTAssertEqual(joined.utf8String, "/tmp/moa/파일.txt")
    }

    func testAppendingDoesNotDoubleSlash() {
        let base = PathBytes("/tmp/moa/")
        let joined = base.appending(Array("a".utf8))
        XCTAssertEqual(joined.utf8String, "/tmp/moa/a")
    }

    func testLastComponent() {
        let p = PathBytes("/tmp/moa/파일.txt")
        XCTAssertEqual(p.lastComponent, Array("파일.txt".utf8))
    }

    func testRemovingLastComponent() {
        let p = PathBytes("/tmp/moa/파일.txt")
        XCTAssertEqual(p.removingLastComponent().utf8String, "/tmp/moa")
    }

    /// 파일시스템 이름은 UTF-8 이 아닐 수 있다. 바이트가 그대로 보존돼야 한다.
    func testPreservesInvalidUTF8Bytes() {
        let broken: [UInt8] = [0xFF, 0xFE, 0x41]
        let p = PathBytes(broken)
        XCTAssertEqual(p.bytes, broken)
        XCTAssertNil(p.utf8String)
    }

    /// NFD 와 NFC 는 서로 다른 바이트열이어야 한다.
    func testNFDAndNFCDifferAsBytes() {
        let nfd = PathBytes("한.txt".decomposedStringWithCanonicalMapping)
        let nfc = PathBytes("한.txt".precomposedStringWithCanonicalMapping)
        XCTAssertNotEqual(nfd.bytes, nfc.bytes)
        XCTAssertEqual(nfc.bytes, [0xED, 0x95, 0x9C, 0x2E, 0x74, 0x78, 0x74])
    }
}
