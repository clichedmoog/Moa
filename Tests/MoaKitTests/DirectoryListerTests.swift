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

    // MARK: - F1 회귀: getattrlist 버퍼가 실제 이름보다 작을 때

    /// getattrlist 는 버퍼가 모자라도 ERANGE 를 돌려주지 않고 status == 0 과 함께
    /// "실제" attr_length·attr_dataoffset 을 채운다. 버퍼 밖을 읽지 않고 한 번만
    /// 재시도해서 정확한 바이트를 돌려줘야 한다.
    ///
    /// 이 저장소가 마운트된 APFS 볼륨은 파일명 컴포넌트 하나가 255 UTF-16 유닛을
    /// 넘을 수 없어서(각 자모는 3바이트) 기본 2048 바이트 버퍼가 실전에서 모자라는
    /// 경우를 실제 파일명으로는 재현할 수 없다. 그래서 내부 시임으로 초기 버퍼를
    /// 일부러 작게 줘서 재시도 경로 자체를 강제로 태운다.
    func testNameVerifierRetriesWhenInitialBufferIsTooSmall() {
        let longName = TestSupport.nfd(String(repeating: "한", count: 60)) + Array(".txt".utf8)
        let path = TestSupport.makeFile(named: longName, in: dir)
        XCTAssertEqual(NameVerifier.onDiskName(of: path, initialBufferSize: 16), longName)
    }

    /// 이 볼륨이 실제로 허용하는 가장 긴 파일명 컴포넌트에서도 정확한 바이트를
    /// 돌려줘야 한다. `open` 이 실패하는 지점까지 이분 탐색으로 좁혀서 경계를 찾는다.
    func testNameVerifierHandlesMaxComponentLength() {
        let longestName = Self.longestAcceptedName(in: dir)
        let path = TestSupport.makeFile(named: longestName, in: dir)
        XCTAssertEqual(NameVerifier.onDiskName(of: path), longestName)
    }

    // MARK: - F3 회귀: classifyViaLstat 시임 (DT_UNKNOWN 폴백)

    func testClassifyViaLstatDetectsFile() {
        let path = TestSupport.makeFile(named: Array("f.txt".utf8), in: dir)
        XCTAssertEqual(DirectoryLister.classifyViaLstat(path), .file)
    }

    func testClassifyViaLstatDetectsDirectory() {
        let path = TestSupport.makeDir(named: Array("d".utf8), in: dir)
        XCTAssertEqual(DirectoryLister.classifyViaLstat(path), .directory)
    }

    func testClassifyViaLstatDetectsSymlink() {
        let target = TestSupport.makeFile(named: Array("target.txt".utf8), in: dir)
        let link = TestSupport.makeSymlink(named: Array("link".utf8), to: target, in: dir)
        XCTAssertEqual(DirectoryLister.classifyViaLstat(link), .symlink)
    }

    // MARK: - 최대 파일명 길이 탐색 헬퍼

    /// `dir` 이 있는 볼륨에서 `open` 이 성공하는 가장 긴 ASCII 파일명을 찾는다.
    /// 성공 길이를 배증하며 상한을 찾은 뒤, 이분 탐색으로 성공/실패 경계를 좁힌다.
    private static func longestAcceptedName(in dir: PathBytes) -> [UInt8] {
        precondition(canCreate(length: 1, in: dir), "1바이트 이름도 생성하지 못했다")
        var low = 1
        var high = 2
        while canCreate(length: high, in: dir) {
            low = high
            high *= 2
            precondition(high <= 8192, "예상보다 훨씬 긴 이름이 허용된다 — 가정을 다시 확인해야 한다")
        }
        while high - low > 1 {
            let mid = (low + high) / 2
            if canCreate(length: mid, in: dir) {
                low = mid
            } else {
                high = mid
            }
        }
        return name(ofLength: low)
    }

    private static func name(ofLength length: Int) -> [UInt8] {
        Array(repeating: UInt8(ascii: "a"), count: length)
    }

    private static func canCreate(length: Int, in dir: PathBytes) -> Bool {
        let candidate = dir.appending(name(ofLength: length))
        let fd = candidate.withCString { open($0, O_CREAT | O_WRONLY | O_EXCL, 0o644) }
        guard fd >= 0 else { return false }
        close(fd)
        _ = candidate.withCString { unlink($0) }
        return true
    }
}
