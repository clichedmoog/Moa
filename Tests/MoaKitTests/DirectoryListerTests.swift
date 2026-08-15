import XCTest
@testable import MoaKit

final class DirectoryListerTests: XCTestCase {

    var dir: PathBytes!

    override func setUp() {
        super.setUp()
        dir = TestSupport.makeTempDir()
    }

    override func tearDown() {
        TestSupport.remove(dir)
        super.tearDown()
    }

    /// 디스크에 NFD 로 저장된 이름은 NFD 바이트 그대로 나와야 한다.
    func testReturnsRawBytesWithoutNormalizing() throws {
        TestSupport.makeFile(named: TestSupport.nfd("한.txt"), in: dir)
        let entries = try DirectoryLister.entries(in: dir)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, TestSupport.nfd("한.txt"))
    }

    /// NFC 로 저장한 이름도 그대로 나와야 한다.
    func testReturnsNFCBytesUnchanged() throws {
        TestSupport.makeFile(named: TestSupport.nfc("한.txt"), in: dir)
        let entries = try DirectoryLister.entries(in: dir)
        XCTAssertEqual(entries[0].name, TestSupport.nfc("한.txt"))
    }

    func testExcludesDotAndDotDot() throws {
        TestSupport.makeFile(named: Array("a.txt".utf8), in: dir)
        let entries = try DirectoryLister.entries(in: dir)
        XCTAssertEqual(entries.map(\.name), [Array("a.txt".utf8)])
    }

    func testClassifiesKinds() throws {
        TestSupport.makeFile(named: Array("file.txt".utf8), in: dir)
        TestSupport.makeDir(named: Array("folder".utf8), in: dir)
        let target = dir.appending(Array("file.txt".utf8))
        TestSupport.makeSymlink(named: Array("link".utf8), to: target, in: dir)

        let entries = try DirectoryLister.entries(in: dir)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { (String(decoding: $0.name, as: UTF8.self), $0.kind) })

        XCTAssertEqual(byName["file.txt"], .file)
        XCTAssertEqual(byName["folder"], .directory)
        XCTAssertEqual(byName["link"], .symlink, "심볼릭 링크는 대상이 아니라 링크 자체로 분류돼야 한다")
    }

    func testThrowsOnMissingDirectory() {
        let missing = dir.appending(Array("없는폴더".utf8))
        XCTAssertThrowsError(try DirectoryLister.entries(in: missing))
    }

    func testNameVerifierReturnsOnDiskBytes() {
        let path = TestSupport.makeFile(named: TestSupport.nfd("한.txt"), in: dir)
        XCTAssertEqual(NameVerifier.onDiskName(of: path), TestSupport.nfd("한.txt"))
    }

    func testNameVerifierReturnsNilForMissingPath() {
        let missing = dir.appending(Array("없음.txt".utf8))
        XCTAssertNil(NameVerifier.onDiskName(of: missing))
    }

    /// 심볼릭 링크를 따라가지 않고 링크 자신의 이름을 돌려줘야 한다.
    func testNameVerifierDoesNotFollowSymlinks() {
        let target = TestSupport.makeFile(named: Array("target.txt".utf8), in: dir)
        let link = TestSupport.makeSymlink(named: Array("링크".utf8), to: target, in: dir)
        XCTAssertEqual(NameVerifier.onDiskName(of: link), Array("링크".utf8))
    }
}
