import XCTest
import ZIPFoundation
@testable import MoaKit

final class ZipWriterTests: XCTestCase {

    var dir: PathBytes!
    var output: URL!

    override func setUp() {
        super.setUp()
        dir = TestSupport.makeTempDir()
        output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("moa-test-\(getpid()).zip")
        try? FileManager.default.removeItem(at: output)
    }

    override func tearDown() {
        TestSupport.remove(dir)
        try? FileManager.default.removeItem(at: output)
        super.tearDown()
    }

    func testExcludesMacOnlyFiles() {
        XCTAssertTrue(ZipExclusions.shouldExclude(name: Array(".DS_Store".utf8)))
        XCTAssertTrue(ZipExclusions.shouldExclude(name: Array("._resource".utf8)))
        XCTAssertTrue(ZipExclusions.shouldExclude(name: Array(".Spotlight-V100".utf8)))
        XCTAssertTrue(ZipExclusions.shouldExclude(name: Array(".Trashes".utf8)))
        XCTAssertTrue(ZipExclusions.shouldExclude(name: Array(".fseventsd".utf8)))
        XCTAssertTrue(ZipExclusions.shouldExclude(name: Array("__MACOSX".utf8)))
    }

    func testKeepsNormalFiles() {
        XCTAssertFalse(ZipExclusions.shouldExclude(name: Array("문서.txt".utf8)))
        XCTAssertFalse(ZipExclusions.shouldExclude(name: Array("_underscore.txt".utf8)))
    }

    /// 디스크에 NFD 로 저장된 파일이라도 ZIP 엔트리는 NFC 여야 한다.
    /// 이것이 exFAT USB 시나리오의 해법이다.
    func testWritesNFCEntryNamesFromNFDFiles() throws {
        TestSupport.makeFile(named: TestSupport.nfd("한글문서.txt"), in: dir, contents: "내용")

        _ = try ZipWriter.write(roots: [dir], to: output)

        // 엔트리 경로에는 루트 폴더 이름이 앞에 붙는다. 마지막 요소만 비교한다.
        let names = try entryNameBytes(in: output)
        XCTAssertTrue(names.contains { $0.hasSuffix(TestSupport.nfc("한글문서.txt")) },
                      "ZIP 엔트리명이 NFC 여야 한다")
        XCTAssertFalse(names.contains { $0.hasSuffix(TestSupport.nfd("한글문서.txt")) },
                       "NFD 엔트리가 남아 있으면 안 된다")
    }

    /// UTF-8 플래그가 없으면 윈도우에서 이름이 깨진다.
    /// ditto 와 zip 명령이 바로 이 플래그를 세우지 않는다.
    func testSetsUTF8Flag() throws {
        TestSupport.makeFile(named: TestSupport.nfd("한글.txt"), in: dir)

        _ = try ZipWriter.write(roots: [dir], to: output)

        let archive = try Archive(url: output, accessMode: .read)
        for entry in archive where entry.type == .file {
            let raw = try XCTUnwrap(entry.path(using: .isoLatin1).data(using: .isoLatin1))
            XCTAssertNotNil(String(data: raw, encoding: .utf8),
                            "엔트리명이 UTF-8 로 저장돼야 한다")
        }
    }

    /// ZIPFoundation 기본값은 무압축이다. deflate 를 명시하지 않으면 용량이 그대로다.
    func testCompressesWithDeflate() throws {
        let repeated = String(repeating: "반복되는 내용 ", count: 500)
        TestSupport.makeFile(named: Array("big.txt".utf8), in: dir, contents: repeated)

        _ = try ZipWriter.write(roots: [dir], to: output)

        let archive = try Archive(url: output, accessMode: .read)
        let entry = try XCTUnwrap(archive.first { $0.path.hasSuffix("big.txt") })
        XCTAssertLessThan(entry.compressedSize, entry.uncompressedSize / 2,
                          "deflate 가 적용되지 않았다")
    }

    func testExcludesMacFilesFromArchive() throws {
        TestSupport.makeFile(named: Array("문서.txt".utf8), in: dir)
        TestSupport.makeFile(named: Array(".DS_Store".utf8), in: dir)
        TestSupport.makeFile(named: Array("._sidecar".utf8), in: dir)

        let result = try ZipWriter.write(roots: [dir], to: output)

        let names = try entryNameBytes(in: output).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertFalse(names.contains { $0.contains(".DS_Store") })
        XCTAssertFalse(names.contains { $0.contains("._sidecar") })
        XCTAssertTrue(names.contains { $0.contains("문서.txt") })
        XCTAssertEqual(result.excludedCount, 2)
    }

    func testPreservesDirectoryStructure() throws {
        let sub = TestSupport.makeDir(named: Array("하위".utf8), in: dir)
        TestSupport.makeFile(named: Array("안쪽.txt".utf8), in: sub)

        _ = try ZipWriter.write(roots: [dir], to: output)

        let names = try entryNameBytes(in: output).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertTrue(names.contains { $0.contains("하위/안쪽.txt") })
    }

    func testDoesNotModifySourceFiles() throws {
        TestSupport.makeFile(named: TestSupport.nfd("원본.txt"), in: dir)

        _ = try ZipWriter.write(roots: [dir], to: output)

        XCTAssertEqual(TestSupport.rawNames(in: dir), [TestSupport.nfd("원본.txt")],
                       "원본 파일명은 건드리지 않아야 한다")
    }

    /// 이 앱이 만든 파일의 이름 자체가 자소분리되면 안 된다.
    /// Foundation 의 파일 생성 API 는 파일명을 NFD 로 쓰므로 별도 처리가 필요하다.
    func testOutputFilenameIsNFCOnDisk() throws {
        TestSupport.makeFile(named: Array("a.txt".utf8), in: dir)
        let outDir = TestSupport.makeTempDir()
        defer { TestSupport.remove(outDir) }

        // 저장 패널이 돌려줄 법한 형태 — Foundation URL 경유
        let target = URL(fileURLWithPath: outDir.displayString)
            .appendingPathComponent("자료모음.zip")
        _ = try ZipWriter.write(roots: [dir], to: target)

        XCTAssertEqual(TestSupport.rawNames(in: outDir), [TestSupport.nfc("자료모음.zip")],
                       "만들어진 ZIP 의 파일명이 디스크에 NFC 로 있어야 한다")
    }

    /// 압축 대상 폴더 안에 저장해도 아카이브가 자기 자신을 포함하지 않아야 한다.
    func testDestinationInsideSourceTreeIsSafe() throws {
        TestSupport.makeFile(named: Array("문서.txt".utf8), in: dir)
        let target = URL(fileURLWithPath: dir.displayString)
            .appendingPathComponent("결과.zip")

        let result = try ZipWriter.write(roots: [dir], to: target)

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        let names = try entryNameBytes(in: target).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertFalse(names.contains { $0.hasSuffix("결과.zip") },
                       "아카이브가 자기 자신을 포함하면 안 된다")
        XCTAssertEqual(result.entryCount, 1)
    }

    func testPlacementOverwritesExistingDestination() throws {
        TestSupport.makeFile(named: Array("새것.txt".utf8), in: dir)
        try Data("이전 내용".utf8).write(to: output)

        _ = try ZipWriter.write(roots: [dir], to: output)

        let names = try entryNameBytes(in: output).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertTrue(names.contains { $0.hasSuffix("새것.txt") },
                      "기존 파일이 있어도 새 아카이브로 대체돼야 한다")
    }

    // MARK: - F2: __MACOSX 하위 트리 제외

    /// __MACOSX 디렉터리를 제외 대상으로 판정해도, 마지막 요소만 보면 그 안의 파일은
    /// 그대로 살아남는다. 경로의 모든 구성 요소를 검사해야 한다.
    func testExcludesNestedMacOSXSubtree() throws {
        let macosx = TestSupport.makeDir(named: Array("__MACOSX".utf8), in: dir)
        TestSupport.makeFile(named: Array("leaked.txt".utf8), in: macosx)
        TestSupport.makeFile(named: Array("정상.txt".utf8), in: dir)

        let result = try ZipWriter.write(roots: [dir], to: output)

        let names = try entryNameBytes(in: output).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertFalse(names.contains { $0.contains("leaked.txt") },
                       "__MACOSX 안의 파일은 엔트리가 되면 안 된다")
        XCTAssertTrue(names.contains { $0.contains("정상.txt") })
        XCTAssertTrue(result.omitted.contains { $0.path.hasSuffix("leaked.txt") },
                      "제외된 항목은 omitted 에 이름이 남아야 한다")
    }

    // MARK: - F3: 빠진 항목은 세는 게 아니라 이름을 남긴다

    /// 소켓·FIFO 같은 특수 파일은 어떤 카운터에도 잡히지 않고 사라졌었다.
    func testSpecialFileIsRecordedInOmitted() throws {
        let fifoPath = dir.appending(Array("파이프".utf8))
        guard fifoPath.withCString({ mkfifo($0, 0o644) }) == 0 else {
            throw XCTSkip("이 환경에서 mkfifo 로 FIFO 를 만들 수 없다")
        }

        let result = try ZipWriter.write(roots: [dir], to: output)

        XCTAssertEqual(result.entryCount, 0)
        XCTAssertTrue(result.omitted.contains { $0.path.hasSuffix("파이프") },
                      "특수 파일은 omitted 에 이름과 이유가 남아야 한다")
    }

    /// 심볼릭 링크는 TreeWalker 가 items 와 skipped 양쪽에 같은 경로로 올린다.
    /// omitted 에는 정확히 한 번만 남아야 한다 — 두 번 남으면 사용자가 같은 파일이
    /// 두 개 빠진 것처럼 오해한다.
    func testSymlinkAppearsExactlyOnceInOmitted() throws {
        let targetFile = TestSupport.makeFile(named: Array("대상.txt".utf8), in: dir)
        let link = TestSupport.makeSymlink(named: Array("링크".utf8), to: targetFile, in: dir)

        let result = try ZipWriter.write(roots: [dir], to: output)

        let matches = result.omitted.filter { $0.path == link.displayString }
        XCTAssertEqual(matches.count, 1, "심볼릭 링크가 omitted 에 두 번 남으면 안 된다")
        XCTAssertEqual(result.entryCount, 1, "심볼릭 링크의 대상 파일은 정상적으로 포함돼야 한다")
    }

    /// 번들은 내용물이 통째로 빠지는데, stray .DS_Store 하나 제외한 것과 똑같이
    /// 보고되면 안 된다 — 번들이라는 사실과 내용물이 빠졌다는 사실이 남아야 한다.
    func testBundleContentsAreNotedAsOmitted() throws {
        let bundle = TestSupport.makeDir(named: Array("테스트.rtfd".utf8), in: dir)
        TestSupport.makeFile(named: Array("a.rtf".utf8), in: bundle)
        TestSupport.makeFile(named: Array("b.png".utf8), in: bundle)

        let result = try ZipWriter.write(roots: [dir], to: output)

        XCTAssertEqual(result.entryCount, 0, "번들 내용물은 아카이브에 들어가면 안 된다")
        let bundleOmission = result.omitted.first { $0.path.hasSuffix("테스트.rtfd") }
        XCTAssertNotNil(bundleOmission)
        XCTAssertTrue(bundleOmission?.detail.contains("번들") ?? false)
        XCTAssertEqual(result.omitted.count, 1,
                       "번들 내용물 각각이 아니라 번들 자체 하나만 기록돼야 한다")
    }

    // MARK: - F1: 실패한 배치는 목적지에 아무것도 남기지 않는다

    /// open 실패 경로. 목적지 디렉터리에 쓰기 권한이 없으면 copyAcrossVolumes 의
    /// open() 이 실패한다. 이 경로는 애초에 아무것도 쓰지 않으므로 정리할 게 없지만,
    /// "실패한 배치는 목적지에 아무것도 남기지 않는다"는 결과 자체는 이 테스트로도
    /// 확인된다.
    func testFailedCrossVolumeOpenLeavesNothingBehind() throws {
        guard let volume = HFSPlusTestVolume.make() else {
            throw XCTSkip("이 환경에서 hdiutil 로 볼륨을 만들거나 attach 할 수 없다")
        }
        defer { volume.detach() }

        TestSupport.makeFile(named: Array("문서.txt".utf8), in: dir)

        let readOnlyDir = TestSupport.makeDir(named: Array("readonly".utf8), in: volume.mountPoint)
        defer { _ = readOnlyDir.withCString { chmod($0, 0o755) } }
        guard readOnlyDir.withCString({ chmod($0, 0o555) }) == 0 else {
            throw XCTSkip("이 환경에서 chmod 로 디렉터리를 읽기 전용으로 만들 수 없다")
        }

        let target = readOnlyDir.appending(Array("결과.zip".utf8))
        let targetURL = URL(fileURLWithPath: target.displayString)

        XCTAssertThrowsError(try ZipWriter.write(roots: [dir], to: targetURL)) { error in
            guard case ArchivePlacementError.cannotPlace = error else {
                XCTFail("예상한 ArchivePlacementError 가 아니다: \(error)")
                return
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.displayString),
                       "배치 실패 후 목적지에 아무것도 남으면 안 된다")
    }

    /// write 실패 경로(핵심). `RLIMIT_FSIZE` 로 이 프로세스가 만들 수 있는 파일
    /// 크기를 제한해 실제 write(2) 실패를 유도한다 — 디스크를 실제로 채우거나 USB 를
    /// 뽑지 않고 재현할 수 있는 유일한 방법이라 이 환경에서 직접 검증했다. 이 fix
    /// 이전에는 O_TRUNC 로 기존 내용을 지운 뒤 일부만 쓰인 손상된 zip 이 목적지에
    /// 그대로 남았다 — 임시 파일을 거치는 설계 전체가 막으려던 바로 그 상황이
    /// 마지막 한 칸에서 재현된 것이었다.
    func testFailedCrossVolumeWriteLeavesNothingBehind() throws {
        guard let volume = HFSPlusTestVolume.make() else {
            throw XCTSkip("이 환경에서 hdiutil 로 볼륨을 만들거나 attach 할 수 없다")
        }
        defer { volume.detach() }

        // 제한을 걸기 전에, 제한 없는 상태에서 충분히 큰 임시 파일을 미리 만든다.
        // 무작위 영숫자라 deflate 로도 잘 줄어들지 않는다.
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)
        var content: [UInt8] = []
        content.reserveCapacity(50_000)
        for _ in 0..<50_000 { content.append(charset.randomElement()!) }
        let temporary = ArchivePlacement.makeTemporaryURL()
        try Data(content).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let target = volume.mountPoint.appending(Array("결과.zip".utf8))
        let targetURL = URL(fileURLWithPath: target.displayString)

        var originalLimit = rlimit()
        getrlimit(RLIMIT_FSIZE, &originalLimit)
        defer { setrlimit(RLIMIT_FSIZE, &originalLimit) }
        let previousHandler = signal(SIGXFSZ, SIG_IGN)
        defer { signal(SIGXFSZ, previousHandler) }

        var smallLimit = rlimit(rlim_cur: 512, rlim_max: originalLimit.rlim_max)
        guard setrlimit(RLIMIT_FSIZE, &smallLimit) == 0 else {
            throw XCTSkip("이 환경에서 RLIMIT_FSIZE 를 낮출 수 없다")
        }

        XCTAssertThrowsError(try ArchivePlacement.place(temporary: temporary, at: targetURL)) { error in
            guard case ArchivePlacementError.cannotPlace = error else {
                XCTFail("예상한 ArchivePlacementError 가 아니다: \(error)")
                return
            }
        }

        setrlimit(RLIMIT_FSIZE, &originalLimit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.displayString),
                       "write 실패 후 목적지에 손상된 파일이 남으면 안 된다")
    }

    // MARK: - 헬퍼

    /// ZIP 엔트리명의 원시 바이트를 얻는다.
    /// isoLatin1 은 0x00~0xFF 를 U+0000~U+00FF 로 1:1 대응시키므로 왕복이 무손실이다.
    private func entryNameBytes(in url: URL) throws -> [[UInt8]] {
        let archive = try Archive(url: url, accessMode: .read)
        return archive.compactMap { entry in
            guard let data = entry.path(using: .isoLatin1).data(using: .isoLatin1) else { return nil }
            return Array(data)
        }
    }
}

extension Array where Element == UInt8 {
    /// Swift 표준 라이브러리에는 `starts(with:)` 만 있고 접미사 비교가 없다.
    func hasSuffix(_ other: [UInt8]) -> Bool {
        count >= other.count && Array(suffix(other.count)) == other
    }
}
