import XCTest
@testable import MoaKit

final class TreeWalkerTests: XCTestCase {

    var dir: PathBytes!

    override func setUp() {
        super.setUp()
        dir = TestSupport.makeTempDir()
    }

    override func tearDown() {
        TestSupport.remove(dir)
        super.tearDown()
    }

    /// 가장 중요한 성질. 자식이 부모보다 먼저 나와야 한다.
    /// 그렇지 않으면 부모 이름을 바꾼 순간 자식 경로가 전부 무효가 된다.
    func testCollectsChildrenBeforeParents() {
        let parent = TestSupport.makeDir(named: Array("부모".utf8), in: dir)
        TestSupport.makeFile(named: Array("자식.txt".utf8), in: parent)

        let result = TreeWalker.collect(from: [parent])
        let paths = result.items.map(\.path)

        let childIndex = paths.firstIndex { $0.lastComponent == Array("자식.txt".utf8) }
        let parentIndex = paths.firstIndex { $0.lastComponent == Array("부모".utf8) }
        XCTAssertNotNil(childIndex)
        XCTAssertNotNil(parentIndex)
        XCTAssertLessThan(childIndex!, parentIndex!, "자식이 부모보다 먼저 와야 한다")
    }

    func testCollectsNestedDepthFirst() {
        let a = TestSupport.makeDir(named: Array("a".utf8), in: dir)
        let b = TestSupport.makeDir(named: Array("b".utf8), in: a)
        TestSupport.makeFile(named: Array("c.txt".utf8), in: b)

        let result = TreeWalker.collect(from: [a])
        let names = result.items.map { String(decoding: $0.path.lastComponent, as: UTF8.self) }
        XCTAssertEqual(names, ["c.txt", "b", "a"])
    }

    /// 심볼릭 링크는 이름만 바꾸고 안으로 들어가지 않는다.
    /// 들어가면 링크 하나로 엉뚱한 트리 전체가 대상이 된다.
    func testDoesNotFollowSymlinks() {
        let outside = TestSupport.makeDir(named: Array("바깥".utf8), in: dir)
        TestSupport.makeFile(named: Array("건드리면안됨.txt".utf8), in: outside)

        let root = TestSupport.makeDir(named: Array("루트".utf8), in: dir)
        TestSupport.makeSymlink(named: Array("링크".utf8), to: outside, in: root)

        let result = TreeWalker.collect(from: [root])
        let names = result.items.map { String(decoding: $0.path.lastComponent, as: UTF8.self) }

        XCTAssertTrue(names.contains("링크"), "링크 자신은 이름 변환 대상이다")
        XCTAssertFalse(names.contains("건드리면안됨.txt"), "링크를 따라가면 안 된다")
        XCTAssertTrue(result.skipped.contains { $0.reason == .symlink })
    }

    /// 번들 패키지는 이름만 바꾸고 내부는 건드리지 않는다.
    func testDoesNotDescendIntoBundles() {
        let bundle = TestSupport.makeDir(named: Array("테스트.rtfd".utf8), in: dir)
        TestSupport.makeFile(named: Array("TXT.rtf".utf8), in: bundle)

        let result = TreeWalker.collect(from: [dir])
        let names = result.items.map { String(decoding: $0.path.lastComponent, as: UTF8.self) }

        XCTAssertTrue(names.contains("테스트.rtfd"))
        XCTAssertFalse(names.contains("TXT.rtf"), "번들 내부로 들어가면 안 된다")
        XCTAssertTrue(result.skipped.contains { $0.reason == .bundle })
    }

    /// 숨김 항목은 이름도 바꾸지 않고 내부도 보지 않는다.
    /// .git 내부를 건드리면 저장소가 깨진다.
    func testSkipsHiddenItemsEntirely() {
        let git = TestSupport.makeDir(named: Array(".git".utf8), in: dir)
        TestSupport.makeFile(named: Array("HEAD".utf8), in: git)
        TestSupport.makeFile(named: Array(".DS_Store".utf8), in: dir)
        TestSupport.makeFile(named: Array("보이는파일.txt".utf8), in: dir)

        let result = TreeWalker.collect(from: [dir])
        let names = result.items.map { String(decoding: $0.path.lastComponent, as: UTF8.self) }

        XCTAssertEqual(names, ["보이는파일.txt", String(decoding: dir.lastComponent, as: UTF8.self)])
        XCTAssertFalse(names.contains("HEAD"))
        XCTAssertTrue(result.skipped.contains { $0.reason == .hidden })
    }

    func testAcceptsPlainFileAsRoot() {
        let file = TestSupport.makeFile(named: Array("혼자.txt".utf8), in: dir)
        let result = TreeWalker.collect(from: [file])
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].path.lastComponent, Array("혼자.txt".utf8))
    }

    /// 접근할 수 없는 디렉터리를 만나도 크래시하지 않고 나머지를 계속 처리해야 한다.
    func testSurvivesUnreadableDirectory() {
        let locked = TestSupport.makeDir(named: Array("잠긴폴더".utf8), in: dir)
        TestSupport.makeFile(named: Array("정상.txt".utf8), in: dir)
        _ = locked.withCString { chmod($0, 0o000) }
        defer { _ = locked.withCString { chmod($0, 0o755) } }

        let result = TreeWalker.collect(from: [dir])
        let names = result.items.map { String(decoding: $0.path.lastComponent, as: UTF8.self) }
        XCTAssertTrue(names.contains("정상.txt"))
    }
}
