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

    /// 번들 자신의 이름이 이미 NFC 라 바뀌지 않는 경우다 — "변환됨" 줄이 없으니
    /// 병합할 대상도 없고, "건너뜀" 에 그대로 남아야 한다. 번들 자신이 NFD 라서
    /// 바뀌는 경우(그래서 "변환됨" 한 줄에 병합돼야 하는 경우)는
    /// `testRenamedBundleAppearsOnceWithSkipNoteMerged` 가 따로 다룬다.
    func testReportsSkippedItems() {
        let bundle = TestSupport.makeDir(named: TestSupport.nfc("문서.rtfd"), in: dir)
        TestSupport.makeFile(named: TestSupport.nfd("안쪽.rtf"), in: bundle)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [dir]))

        XCTAssertTrue(report.skipped.contains { $0.detail.contains("번들") })
        XCTAssertEqual(TestSupport.rawNames(in: bundle), [TestSupport.nfd("안쪽.rtf")],
                       "번들 내부는 변환되지 않아야 한다")
    }

    // MARK: - F1: 같은 경로가 변환됨과 건너뜀에 동시에 나타나면 안 된다

    /// TreeWalker 는 심볼릭 링크를 items 와 skipped 양쪽에 같은 경로로 올린다.
    /// 링크 이름 자체가 NFD 라 바뀌었다면 "변환됨" 에 한 줄만 있어야 하고, 그 줄에
    /// "내부는 건드리지 않음" 안내가 붙어야 한다. 별도의 "건너뜀" 줄이 생기면
    /// 같은 파일이 모순된 두 줄로 보고되는 것이다.
    func testRenamedSymlinkAppearsOnceWithSkipNoteMerged() {
        let target = TestSupport.makeFile(named: Array("target.txt".utf8), in: dir)
        TestSupport.makeSymlink(named: TestSupport.nfd("링크"), to: target, in: dir)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [dir]))

        let renamedRows = report.renamed.filter { $0.path.contains("링크") }
        let skippedRows = report.skipped.filter { $0.path.contains("링크") }
        let failedRows = report.failed.filter { $0.path.contains("링크") }

        XCTAssertEqual(renamedRows.count, 1, "변환됨에 정확히 한 줄이어야 한다")
        XCTAssertEqual(skippedRows.count, 0, "이미 변환됨에 실렸으니 건너뜀에 중복되면 안 된다")
        XCTAssertEqual(failedRows.count, 0)
        XCTAssertTrue(renamedRows.first?.detail.contains("내부는 건드리지 않음") ?? false,
                      "새 이름 옆에 안내가 붙어야 한다")
    }

    /// 번들도 같은 모양의 문제를 겪는다 — 번들 자신의 이름이 NFD 라 바뀌면
    /// 심볼릭 링크와 동일하게 "변환됨" 한 줄로 병합돼야 한다.
    func testRenamedBundleAppearsOnceWithSkipNoteMerged() {
        let bundle = TestSupport.makeDir(named: TestSupport.nfd("문서.rtfd"), in: dir)
        TestSupport.makeFile(named: TestSupport.nfd("안쪽.rtf"), in: bundle)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [dir]))

        let renamedRows = report.renamed.filter { $0.path.contains("문서.rtfd") }
        let skippedRows = report.skipped.filter { $0.path.contains("문서.rtfd") }

        XCTAssertEqual(renamedRows.count, 1, "변환됨에 정확히 한 줄이어야 한다")
        XCTAssertEqual(skippedRows.count, 0, "이미 변환됨에 실렸으니 건너뜀에 중복되면 안 된다")
        XCTAssertTrue(renamedRows.first?.detail.contains("내부는 건드리지 않음") ?? false)
        XCTAssertEqual(TestSupport.rawNames(in: bundle), [TestSupport.nfd("안쪽.rtf")],
                       "번들 내부는 변환되지 않아야 한다")
    }

    /// 이미 NFC 인 심볼릭 링크는 "변환됨" 줄이 없으므로 병합할 대상이 없다.
    /// "안쪽으로 내려가지 않았다" 는 정보를 잃지 않으려면 건너뜀에는 그대로 남아야 한다.
    func testAlreadyNormalizedSymlinkStillReportsSkipped() {
        let target = TestSupport.makeFile(named: Array("target.txt".utf8), in: dir)
        TestSupport.makeSymlink(named: TestSupport.nfc("링크"), to: target, in: dir)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [dir]))

        XCTAssertTrue(report.skipped.contains { $0.path.contains("링크") && $0.detail.contains("내부는 건드리지 않음") },
                      "링크는 변환되지 않았으니 건너뜀 정보가 남아있어야 한다")
        XCTAssertFalse(report.renamed.contains { $0.path.contains("링크") })
    }

    // MARK: - F2: totalCount 는 실제로 순회한 전체를 반영해야 한다

    /// items 만 세면 번들·숨김·심볼릭 링크로 건너뛰거나 권한 문제로 못 본 항목이
    /// 빠져 사용자에게 실제보다 적게 순회한 것처럼 보인다.
    func testPreviewTotalCountIncludesSkippedAndFailures() {
        TestSupport.makeFile(named: TestSupport.nfd("파일.txt"), in: dir)
        TestSupport.makeFile(named: Array(".hidden".utf8), in: dir)
        let locked = TestSupport.makeDir(named: Array("locked".utf8), in: dir)
        _ = locked.withCString { chmod($0, 0o000) }
        defer { _ = locked.withCString { chmod($0, 0o755) } }

        let preview = NormalizationService.preview(roots: [dir])

        XCTAssertGreaterThanOrEqual(preview.walk.skipped.count, 1)
        XCTAssertGreaterThanOrEqual(preview.walk.failures.count, 1)
        XCTAssertEqual(preview.totalCount,
                       preview.walk.items.count + preview.walk.skipped.count + preview.walk.failures.count)
    }

    // MARK: - F3: 볼륨 경고는 모든 루트를 봐야 한다

    /// `roots.first` 만 보면 두 번째 이후 루트가 정규화를 보존하지 않는 볼륨이어도
    /// 경고가 뜨지 않는다. 실제 HFS+ 볼륨을 두 번째 루트로 넣어 확인한다.
    func testVolumeWarningNamesNonFirstRootFilesystem() throws {
        guard let volume = HFSPlusTestVolume.make() else {
            throw XCTSkip("이 환경에서 hdiutil 로 HFS+ 이미지를 만들거나 attach 할 수 없다")
        }
        defer { volume.detach() }

        let preview = NormalizationService.preview(roots: [dir, volume.mountPoint])

        guard let warning = preview.volumeWarning else {
            return XCTFail("두 번째 루트가 정규화를 보존하지 않는데도 경고가 없다")
        }
        XCTAssertTrue(warning.contains("hfs"), "경고에 두 번째 루트의 파일시스템 이름이 담겨야 한다")
    }

    // MARK: - F4: verificationFailed 는 파이프라인 전체에서 failed 로만 보고돼야 한다

    /// HFS+ 는 rename(2) 이 0 을 반환해도 드라이버가 이름을 NFD 로 되돌린다.
    /// 이걸 "변환됨"으로 보고하면 이 프로젝트가 절대 허용하지 않는 "근거 없는
    /// 성공 보고" 가 된다. preview 부터 run 까지 전체 파이프라인으로 확인한다.
    func testVerificationFailureOnHFSPlusIsReportedAsFailedNotRenamed() throws {
        guard let volume = HFSPlusTestVolume.make() else {
            throw XCTSkip("이 환경에서 hdiutil 로 HFS+ 이미지를 만들거나 attach 할 수 없다")
        }
        defer { volume.detach() }

        TestSupport.makeFile(named: TestSupport.nfd("한글.txt"), in: volume.mountPoint)

        let report = NormalizationService.run(preview: NormalizationService.preview(roots: [volume.mountPoint]))

        XCTAssertTrue(report.failed.contains { $0.path.contains("한글.txt") },
                      "HFS+ 의 verificationFailed 는 failed 로 보고돼야 한다")
        XCTAssertFalse(report.renamed.contains { $0.path.contains("한글.txt") },
                       "되돌려진 rename 을 renamed 로 보고하면 안 된다")
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
