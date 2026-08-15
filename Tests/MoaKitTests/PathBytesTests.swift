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

    /// 빈 경로에 이어붙일 때는 선행 구분자가 생기면 안 된다 (F1).
    func testAppendingOnEmptyPathHasNoLeadingSeparator() {
        let base = PathBytes([])
        let joined = base.appending(Array("file.txt".utf8))
        XCTAssertEqual(joined.utf8String, "file.txt")
    }

    /// 끝에 구분자가 있어도 POSIX `basename` 처럼 동작해야 한다 (F2).
    func testLastComponentIgnoresTrailingSeparator() {
        let p = PathBytes("/tmp/moa/")
        XCTAssertEqual(p.lastComponent, Array("moa".utf8))
    }

    /// 끝에 구분자가 있어도 POSIX `dirname` 처럼 동작해야 한다 (F2).
    func testRemovingLastComponentIgnoresTrailingSeparator() {
        let p = PathBytes("/tmp/moa/")
        XCTAssertEqual(p.removingLastComponent().utf8String, "/tmp")
    }

    /// 내부의 중복 구분자 경계에서도 후행 구분자가 남지 않아야 한다 (F3).
    func testRemovingLastComponentDoesNotLeaveTrailingSeparator() {
        let p = PathBytes("/tmp//moa")
        XCTAssertEqual(p.removingLastComponent().utf8String, "/tmp")
    }

    /// 루트는 정규화를 거쳐도 그대로 `/` 여야 한다.
    func testRootSurvivesCanonicalization() {
        let p = PathBytes("/")
        XCTAssertEqual(p.bytes, [UInt8(ascii: "/")])
    }

    /// 후행 구분자가 여러 개여도 마지막 요소는 동일해야 한다.
    func testLastComponentIgnoresMultipleTrailingSeparators() {
        let p = PathBytes("/tmp/moa///")
        XCTAssertEqual(p.lastComponent, Array("moa".utf8))
    }
}
