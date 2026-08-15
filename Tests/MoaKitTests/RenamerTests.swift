import XCTest
@testable import MoaKit

final class RenamerTests: XCTestCase {

    var dir: PathBytes!

    override func setUp() {
        super.setUp()
        dir = TestSupport.makeTempDir()
    }

    override func tearDown() {
        TestSupport.remove(dir)
        super.tearDown()
    }

    /// 이 프로젝트에서 가장 중요한 테스트.
    /// FileManager.moveItem 으로 구현하면 outcome 은 renamed 인데
    /// 디스크 바이트는 NFD 그대로여서 여기서 걸린다.
    func testRenamesNFDToNFCOnDisk() {
        let path = TestSupport.makeFile(named: TestSupport.nfd("한글.txt"), in: dir)

        let outcome = Renamer.normalizeName(at: path)

        XCTAssertEqual(outcome, .renamed)
        XCTAssertEqual(TestSupport.rawNames(in: dir), [TestSupport.nfc("한글.txt")],
                       "디스크 원시 바이트가 NFC 여야 한다")
    }

    func testSkipsAlreadyNormalizedName() {
        let path = TestSupport.makeFile(named: TestSupport.nfc("한글.txt"), in: dir)

        let outcome = Renamer.normalizeName(at: path)

        XCTAssertEqual(outcome, .alreadyNormalized)
    }

    /// 이미 NFC 인 파일은 rename 하지 않으므로 수정 시각이 보존돼야 한다.
    func testDoesNotTouchModificationDateOfNormalizedFile() throws {
        let path = TestSupport.makeFile(named: TestSupport.nfc("한글.txt"), in: dir)
        var before = stat()
        _ = path.withCString { stat($0, &before) }

        Thread.sleep(forTimeInterval: 1.1)
        _ = Renamer.normalizeName(at: path)

        var after = stat()
        _ = path.withCString { stat($0, &after) }
        XCTAssertEqual(before.st_mtimespec.tv_sec, after.st_mtimespec.tv_sec)
    }

    func testRenamesASCIINameAsNoOp() {
        let path = TestSupport.makeFile(named: Array("report.txt".utf8), in: dir)
        XCTAssertEqual(Renamer.normalizeName(at: path), .alreadyNormalized)
    }

    func testFailsOnMissingFile() {
        let missing = dir.appending(Array("없음.txt".utf8))
        guard case .failed = Renamer.normalizeName(at: missing) else {
            return XCTFail("없는 파일은 failed 여야 한다")
        }
    }

    func testRenamesDirectory() {
        let path = TestSupport.makeDir(named: TestSupport.nfd("폴더"), in: dir)
        XCTAssertEqual(Renamer.normalizeName(at: path), .renamed)
        XCTAssertEqual(TestSupport.rawNames(in: dir), [TestSupport.nfc("폴더")])
    }

    /// 심볼릭 링크는 링크 자신의 이름만 바뀌고 대상은 그대로여야 한다.
    func testRenamesSymlinkItselfNotTarget() {
        let target = TestSupport.makeFile(named: Array("target.txt".utf8), in: dir)
        let link = dir.appending(TestSupport.nfd("링크"))
        _ = target.withCString { targetPtr in
            link.withCString { linkPtr in symlink(targetPtr, linkPtr) }
        }

        XCTAssertEqual(Renamer.normalizeName(at: link), .renamed)

        let names = Set(TestSupport.rawNames(in: dir))
        XCTAssertTrue(names.contains(TestSupport.nfc("링크")))
        XCTAssertTrue(names.contains(Array("target.txt".utf8)), "대상 파일은 그대로여야 한다")
    }
}
