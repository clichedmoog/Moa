import XCTest
import ZIPFoundation
@testable import MoaKit

final class ZipCleanerTests: XCTestCase {

    var source: URL!
    var destination: URL!

    override func setUp() {
        super.setUp()
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        source = base.appendingPathComponent("moa-src-\(getpid()).zip")
        destination = base.appendingPathComponent("moa-dst-\(getpid()).zip")
        try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: destination)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: destination)
        super.tearDown()
    }

    func testNormalizesNFDEntryNamesToNFC() throws {
        try makeArchive(entries: [(nfdName("한글문서.txt"), "내용")])

        _ = try ZipCleaner.clean(archiveAt: source, to: destination)

        let names = try entryNameBytes(in: destination)
        XCTAssertEqual(names, [TestSupport.nfc("한글문서.txt")])
    }

    func testRemovesMacOnlyEntries() throws {
        try makeArchive(entries: [
            ("문서.txt", "내용"),
            (".DS_Store", "junk"),
            ("__MACOSX/._문서.txt", "fork"),
            ("._sidecar", "fork")
        ])

        let result = try ZipCleaner.clean(archiveAt: source, to: destination)

        let names = try entryNameBytes(in: destination).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(names, ["문서.txt"])
        XCTAssertEqual(result.excludedCount, 3)
    }

    func testPreservesFileContents() throws {
        let payload = String(repeating: "데이터 ", count: 300)
        try makeArchive(entries: [(nfdName("자료.txt"), payload)])

        _ = try ZipCleaner.clean(archiveAt: source, to: destination)

        let archive = try Archive(url: destination, accessMode: .read)
        let entry = try XCTUnwrap(archive.first { $0.type == .file })
        var data = Data()
        _ = try archive.extract(entry, skipCRC32: true) { data.append($0) }
        XCTAssertEqual(String(data: data, encoding: .utf8), payload)
    }

    func testAppliesDeflate() throws {
        let payload = String(repeating: "반복 ", count: 1000)
        try makeArchive(entries: [("big.txt", payload)], compression: .none)

        _ = try ZipCleaner.clean(archiveAt: source, to: destination)

        let archive = try Archive(url: destination, accessMode: .read)
        let entry = try XCTUnwrap(archive.first { $0.type == .file })
        XCTAssertLessThan(entry.compressedSize, entry.uncompressedSize / 2)
    }

    func testKeepsSourceUntouched() throws {
        try makeArchive(entries: [(nfdName("원본.txt"), "내용")])
        let before = try Data(contentsOf: source)

        _ = try ZipCleaner.clean(archiveAt: source, to: destination)

        XCTAssertEqual(try Data(contentsOf: source), before, "원본 아카이브는 그대로여야 한다")
    }

    /// 저장 패널이 제안한 `-정리됨` 을 지우고 원래 이름으로 저장하는 건 자연스러운 행동이다.
    /// 목적지가 원본과 같은 파일이어도 깨지지 않고 제자리에서 정리돼야 한다.
    func testCanOverwriteSourceInPlace() throws {
        try makeArchive(entries: [
            (nfdName("한글문서.txt"), "내용"),
            (".DS_Store", "junk")
        ])

        let result = try ZipCleaner.clean(archiveAt: source, to: source)

        XCTAssertEqual(result.entryCount, 1)
        let names = try entryNameBytes(in: source)
        XCTAssertEqual(names, [TestSupport.nfc("한글문서.txt")],
                       "제자리 정리 후 엔트리명이 NFC 이고 맥 전용 파일이 빠져야 한다")

        // 내용까지 온전한지 확인한다. 이름만 맞고 데이터가 깨지면 최악이다.
        let archive = try Archive(url: source, accessMode: .read)
        let entry = try XCTUnwrap(archive.first { $0.type == .file })
        var data = Data()
        _ = try archive.extract(entry, skipCRC32: true) { data.append($0) }
        XCTAssertEqual(String(data: data, encoding: .utf8), "내용")
    }

    /// 결과 파일의 이름 자체도 NFC 여야 한다.
    /// Foundation 의 파일 생성 API 는 파일명을 NFD 로 쓰므로 별도 처리가 필요하다.
    func testOutputFilenameIsNFCOnDisk() throws {
        try makeArchive(entries: [("a.txt", "x")])
        let outDir = TestSupport.makeTempDir()
        defer { TestSupport.remove(outDir) }
        let target = URL(fileURLWithPath: outDir.displayString)
            .appendingPathComponent("정리한자료.zip")

        _ = try ZipCleaner.clean(archiveAt: source, to: target)

        XCTAssertEqual(TestSupport.rawNames(in: outDir), [TestSupport.nfc("정리한자료.zip")])
    }

    func testDefaultDestinationAppendsSuffix() {
        let input = URL(fileURLWithPath: "/tmp/사진모음.zip")
        XCTAssertEqual(ZipCleaner.defaultDestination(for: input).lastPathComponent,
                       "사진모음-정리됨.zip")
    }

    func testThrowsOnUnreadableArchive() throws {
        try Data("이건 zip 이 아니다".utf8).write(to: source)
        XCTAssertThrowsError(try ZipCleaner.clean(archiveAt: source, to: destination))
    }

    /// Zip Slip 방지. 디스크에 풀지 않으므로 경로 탈출이 불가능하다.
    ///
    /// 탈출 위치는 하드코딩한 `.deletingLastPathComponent()` 횟수가 아니라 **엔트리
    /// 이름 자체를 목적지 디렉터리에 상대 적용해 표준화**해서 구한다. 이렇게 하면
    /// 픽스처의 이름이나 `../` 깊이가 바뀌어도 검증이 저절로 따라간다 — 고정된
    /// 깊이로 손으로 짚으면 픽스처가 바뀔 때 가드가 조용히 어긋난다.
    func testDoesNotWriteOutsideDestination() throws {
        let maliciousName = "../../탈출.txt"
        try makeArchive(entries: [(maliciousName, "악성")])

        _ = try ZipCleaner.clean(archiveAt: source, to: destination)

        let escapePath = destination.deletingLastPathComponent()
            .appendingPathComponent(maliciousName)
            .standardizedFileURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: escapePath.path))
    }

    /// 인코딩 판정 2단계: UTF-8 로 디코드되지 않으면 CP949(윈도우 한국어판)를 시도한다.
    ///
    /// `Archive.addEntry(with: String, ...)` 는 ZIPFoundation 이 내부적으로 항상
    /// `Data(path.utf8)` 로 이름을 인코딩하고 UTF-8 플래그를 세운다 — 공개 API 로는
    /// CP949 원시 바이트를 담은 엔트리를 만들 방법이 없다. 그래서 이 테스트는 최소
    /// 유효 ZIP 을 바이트 단위로 직접 구성해, 실제 윈도우 한국어판이 만드는 zip과
    /// 같은 모양(UTF-8 플래그 꺼짐, 이름은 CP949 원시 바이트)을 재현한다.
    func testDecodesCP949EntryNames() throws {
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        let nameBytes = try XCTUnwrap("윈도우.txt".data(using: cp949)).map { $0 }

        try makeRawArchive(nameBytes: nameBytes, contents: "x")

        let result = try ZipCleaner.clean(archiveAt: source, to: destination)

        XCTAssertEqual(result.entryCount, 1)
        let names = try entryNameBytes(in: destination)
        XCTAssertEqual(names, [TestSupport.nfc("윈도우.txt")])
    }

    /// 인코딩 판정 3단계: UTF-8 도, CP949 도 아니면 이름을 지어내지 않고 원본을
    /// 유지한다 — 단, 그 "원본"(`entry.path`)이 빈 문자열로 떨어지는 모순된 경우까지
    /// 포함해서다.
    ///
    /// 이 엔트리는 UTF-8 플래그(일반 목적 비트 11)를 세운 채로 UTF-8 도 CP949 도
    /// 아닌 원시 바이트를 이름으로 갖는다 — ZIPFoundation 의 `entry.path` 는 이 경우
    /// `String(pathData:encoding:.utf8) ?? ""` 로 빈 문자열을 내놓는다. 엔트리는
    /// 어차피 새 아카이브에 들어가야 하므로(제외 대상이 아니다), 빈 이름을 그대로
    /// 쓰지 않고 원시 바이트에서 결정적으로 합성한 이름을 써야 한다.
    func testFallsBackToPlaceholderWhenNameIsUndecodable() throws {
        let nameBytes = Array("bad".utf8) + [0xFF, 0xFE] + Array(".txt".utf8)
        try makeRawArchive(nameBytes: nameBytes, contents: "x", generalPurposeBitFlag: 2048)

        let result = try ZipCleaner.clean(archiveAt: source, to: destination)

        XCTAssertEqual(result.entryCount, 1, "제외 대상이 아니므로 그대로 담겨야 한다")
        let names = try entryNameBytes(in: destination)
        XCTAssertEqual(names.count, 1)
        XCTAssertFalse(names[0].isEmpty, "이름 없는 엔트리를 만들면 안 된다")
    }

    // MARK: - 헬퍼

    private func nfdName(_ s: String) -> String {
        s.decomposedStringWithCanonicalMapping
    }

    private func makeArchive(entries: [(String, String)],
                             compression: CompressionMethod = .deflate) throws {
        let archive = try Archive(url: source, accessMode: .create)
        for (name, contents) in entries {
            let data = Data(contents.utf8)
            try archive.addEntry(with: name, type: .file,
                                 uncompressedSize: Int64(data.count),
                                 compressionMethod: compression) { position, size in
                let start = Int(position)
                return data.subdata(in: start..<min(start + size, data.count))
            }
        }
    }

    private func entryNameBytes(in url: URL) throws -> [[UInt8]] {
        let archive = try Archive(url: url, accessMode: .read)
        return archive.compactMap { entry in
            guard let data = entry.path(using: .isoLatin1).data(using: .isoLatin1) else { return nil }
            return Array(data)
        }
    }

    /// 표준 ZIP 형식을 바이트 단위로 직접 조립한다(STORED 압축, 항목 1개).
    ///
    /// `ZIPFoundation` 의 쓰기 API 는 항상 이름을 UTF-8 로 인코딩하고 UTF-8 플래그를
    /// 세우므로, 그 플래그가 꺼진(CP949 등 레거시 zip) 엔트리나 플래그는 섰지만
    /// 원시 바이트가 실제로는 유효한 UTF-8 이 아닌 모순된 엔트리는 이 방법이
    /// 아니면 만들 수 없다. CRC-32 는 0으로 둔다 — `ZipCleaner` 는 원본을 읽을 때
    /// `skipCRC32: true` 를 쓰므로 검증하지 않는다.
    private func makeRawArchive(nameBytes: [UInt8], contents: String,
                                generalPurposeBitFlag: UInt16 = 0) throws {
        let payload = Data(contents.utf8)
        var data = Data()

        // Local File Header (30바이트 고정 필드 + 파일명)
        data.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])   // local file header signature
        data.append(le16(20))                               // version needed to extract
        data.append(le16(generalPurposeBitFlag))             // general purpose bit flag
        data.append(le16(0))                                // compression method: stored
        data.append(le16(0))                                // last mod file time
        data.append(le16(0x21))                              // last mod file date (1980-01-01)
        data.append(le32(0))                                 // crc-32 (검증 안 함)
        data.append(le32(UInt32(payload.count)))             // compressed size
        data.append(le32(UInt32(payload.count)))             // uncompressed size
        data.append(le16(UInt16(nameBytes.count)))           // file name length
        data.append(le16(0))                                 // extra field length
        data.append(contentsOf: nameBytes)
        data.append(payload)

        let centralDirectoryOffset = UInt32(data.count)

        // Central Directory File Header (46바이트 고정 필드 + 파일명)
        data.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])   // central directory signature
        data.append(le16(20))                               // version made by (upper byte 0 == MS-DOS)
        data.append(le16(20))                               // version needed to extract
        data.append(le16(generalPurposeBitFlag))             // general purpose bit flag
        data.append(le16(0))                                // compression method
        data.append(le16(0))                                // last mod file time
        data.append(le16(0x21))                              // last mod file date
        data.append(le32(0))                                 // crc-32
        data.append(le32(UInt32(payload.count)))             // compressed size
        data.append(le32(UInt32(payload.count)))             // uncompressed size
        data.append(le16(UInt16(nameBytes.count)))           // file name length
        data.append(le16(0))                                 // extra field length
        data.append(le16(0))                                 // file comment length
        data.append(le16(0))                                 // disk number start
        data.append(le16(0))                                 // internal file attributes
        data.append(le32(0))                                 // external file attributes
        data.append(le32(0))                                 // relative offset of local header
        data.append(contentsOf: nameBytes)

        let centralDirectorySize = UInt32(data.count) - centralDirectoryOffset

        // End Of Central Directory Record (22바이트, 코멘트 없음)
        data.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        data.append(le16(0))                                 // number of this disk
        data.append(le16(0))                                 // disk where central directory starts
        data.append(le16(1))                                 // # of central directory records on this disk
        data.append(le16(1))                                 // total # of central directory records
        data.append(le32(centralDirectorySize))              // size of central directory
        data.append(le32(centralDirectoryOffset))            // offset of start of central directory
        data.append(le16(0))                                 // comment length

        try data.write(to: source)
    }

    private func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }
}
