import XCTest
@testable import MoaKit

final class NormalizationServiceTests: XCTestCase {

    var dir: PathBytes!

    override func setUp() {
        super.setUp()
        dir = TestSupport.makeTempDir()
    }

    override func tearDown() {
        TestSupport.remove(dir)
        super.tearDown()
    }

    /// 임계값 판단의 기준은 "실제 변환 대상"이다.
    /// 이미 NFC 인 파일은 아무리 많아도 카운트에 들어가지 않는다.
    func testPreviewCountsOnlyItemsNeedingChange() {
        TestSupport.makeFile(named: TestSupport.nfd("하나.txt"), in: dir)
        TestSupport.makeFile(named: TestSupport.nfd("둘.txt"), in: dir)
        TestSupport.makeFile(named: TestSupport.nfc("이미정상.txt"), in: dir)
        TestSupport.makeFile(named: Array("ascii.txt".utf8), in: dir)

        let preview = NormalizationService.preview(roots: [dir])

        XCTAssertEqual(preview.targetCount, 2, "NFD 인 2개만 대상이다")
        XCTAssertEqual(preview.totalCount, 5, "순회한 전체는 파일 4개 + 루트 디렉터리 1개")
    }

    func testRunNormalizesNFDAndLeavesOthers() {
        TestSupport.makeFile(named: TestSupport.nfd("변환대상.txt"), in: dir)
        TestSupport.makeFile(named: TestSupport.nfc("이미정상.txt"), in: dir)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [dir]))

        XCTAssertEqual(report.renamed.count, 1)
        XCTAssertEqual(report.failed.count, 0)

        let names = Set(TestSupport.rawNames(in: dir))
        XCTAssertTrue(names.contains(TestSupport.nfc("변환대상.txt")))
        XCTAssertTrue(names.contains(TestSupport.nfc("이미정상.txt")))
    }

    /// bottom-up 이 지켜지는지 실제 파이프라인으로 확인한다.
    /// 부모를 먼저 바꾸면 자식 경로가 무효가 되어 failed 가 생긴다.
    func testRenamesNestedTreeWithoutFailures() {
        let parent = TestSupport.makeDir(named: TestSupport.nfd("부모폴더"), in: dir)
        let child = TestSupport.makeDir(named: TestSupport.nfd("자식폴더"), in: parent)
        TestSupport.makeFile(named: TestSupport.nfd("문서.txt"), in: child)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [parent]))

        XCTAssertEqual(report.failed.count, 0, "실패가 있으면 순회 순서가 잘못된 것이다")
        XCTAssertEqual(report.renamed.count, 3)

        let topNames = TestSupport.rawNames(in: dir)
        XCTAssertEqual(topNames, [TestSupport.nfc("부모폴더")])

        let renamedParent = dir.appending(TestSupport.nfc("부모폴더"))
        XCTAssertEqual(TestSupport.rawNames(in: renamedParent), [TestSupport.nfc("자식폴더")])
    }

    func testReportsSkippedItems() {
        let bundle = TestSupport.makeDir(named: TestSupport.nfd("문서.rtfd"), in: dir)
        TestSupport.makeFile(named: TestSupport.nfd("안쪽.rtf"), in: bundle)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [dir]))

        XCTAssertTrue(report.skipped.contains { $0.detail.contains("번들") })
        XCTAssertEqual(TestSupport.rawNames(in: bundle), [TestSupport.nfd("안쪽.rtf")],
                       "번들 내부는 변환되지 않아야 한다")
    }

    func testCountsAlreadyNormalized() {
        TestSupport.makeFile(named: TestSupport.nfc("가.txt"), in: dir)
        TestSupport.makeFile(named: TestSupport.nfc("나.txt"), in: dir)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [dir]))

        XCTAssertEqual(report.renamed.count, 0)
        XCTAssertGreaterThanOrEqual(report.alreadyNormalized, 2)
    }

    func testNoVolumeWarningOnAPFS() {
        let preview = NormalizationService.preview(roots: [dir])
        XCTAssertNil(preview.volumeWarning)
    }

    /// 순회 중 읽지 못한 것은 "건너뜀"이 아니라 "실패"로 보고돼야 한다.
    /// 이 프로젝트의 제1원칙 — 근거 없는 성공을 보고하지 않는다.
    func testUnreadableDirectoryIsReportedAsFailure() {
        let locked = TestSupport.makeDir(named: TestSupport.nfd("잠긴폴더"), in: dir)
        TestSupport.makeFile(named: TestSupport.nfd("안쪽.txt"), in: locked)
        TestSupport.makeFile(named: TestSupport.nfd("정상.txt"), in: dir)
        _ = locked.withCString { chmod($0, 0o000) }
        defer { _ = locked.withCString { chmod($0, 0o755) } }

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [dir]))

        XCTAssertTrue(report.failed.contains { $0.detail.contains("읽지 못해") },
                      "읽지 못한 폴더는 실패로 보고돼야 한다")
        XCTAssertFalse(report.skipped.contains { $0.path.contains("잠긴폴더") },
                       "실패를 건너뜀 목록에 넣으면 안 된다")
        XCTAssertTrue(report.renamed.contains { $0.path.contains("정상.txt") },
                      "읽을 수 있는 형제는 계속 처리돼야 한다")
    }

    func testMissingRootIsReportedAsFailure() {
        let missing = dir.appending(TestSupport.nfd("없는폴더"))

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [missing]))

        XCTAssertEqual(report.renamed.count, 0)
        XCTAssertTrue(report.failed.contains { $0.detail.contains("접근하지 못함") },
                      "없는 경로가 조용히 사라지면 안 된다")
    }
}
