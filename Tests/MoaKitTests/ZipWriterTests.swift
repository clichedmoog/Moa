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
