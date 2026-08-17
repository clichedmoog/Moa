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

    /// HFS+ 는 rename(2) 이 0 을 반환해도 드라이버가 NFC 로 쓴 이름을 NFD 로 되돌린다.
    /// `.verificationFailed` 가 바로 이 상황을 잡아내려고 존재한다 — 사용자에게
    /// "바꿨다"고 거짓 보고하지 않기 위한, 이 프로젝트에서 가장 사용자 영향이 큰
    /// 안전장치다. APFS(이 스위트의 다른 모든 테스트가 도는 곳)에서는 이 버그가
    /// 재현되지 않으므로 실제 HFS+ 볼륨이 필요하다.
    func testVerificationFailsOnHFSPlusVolume() throws {
        guard let volume = HFSPlusTestVolume.make() else {
            throw XCTSkip("이 환경에서 hdiutil 로 HFS+ 이미지를 만들거나 attach 할 수 없다")
        }
        defer { volume.detach() }

        let path = TestSupport.makeFile(named: TestSupport.nfd("한글.txt"), in: volume.mountPoint)

        let outcome = Renamer.normalizeName(at: path)

        XCTAssertEqual(outcome, .verificationFailed)
        XCTAssertEqual(TestSupport.rawNames(in: volume.mountPoint), [TestSupport.nfd("한글.txt")],
                       "HFS+ 에서는 rename 이 성공을 반환해도 디스크 바이트는 NFD 그대로여야 한다")
    }
}

/// `hdiutil` 로 만든 일회용 HFS+ 디스크 이미지.
///
/// `.verificationFailed` 를 재현하려면 실제 HFS+ 볼륨이 필요하다 — APFS 에는 이 버그가
/// 없다. 이미지·마운트 포인트 이름은 전부 ASCII 이며 `NSTemporaryDirectory()` 아래
/// 만들어진다. `sudo` 나 관리자 권한은 쓰지 않는다: `hdiutil create`/`attach`/`detach`
/// 는 사용자 소유 파일에 대해서는 권한 상승이 필요 없다.
final class HFSPlusTestVolume {
    let mountPoint: PathBytes

    private let imagePath: String
    private var isAttached = true

    private init(mountPoint: PathBytes, imagePath: String) {
        self.mountPoint = mountPoint
        self.imagePath = imagePath
    }

    /// 이미지 생성이나 attach 가 실패하면(예: `hdiutil` 이 제한된 CI 환경) nil 을
    /// 돌려준다. 던지지 않는 이유는 호출부가 `XCTSkip` 으로 조용히 건너뛰게 하려는
    /// 것이다 — `hdiutil` 이 막힌 머신에서 이 테스트가 깨져서는 안 된다.
    static func make() -> HFSPlusTestVolume? {
        let unique = "moa-renamer-hfs-\(getpid())-\(UInt32.random(in: 0..<UInt32.max))"
        let imagePath = NSTemporaryDirectory() + unique + ".dmg"
        let mountDir = NSTemporaryDirectory() + unique + "-mnt"

        guard run("/usr/bin/hdiutil", [
            "create", "-size", "16m", "-fs", "HFS+",
            "-volname", "MoaRenamerHFSTest", "-quiet", imagePath,
        ]) else { return nil }

        // `-mountpoint` 로 지정한 디렉터리는 hdiutil 이 필요하면 알아서 만든다.
        // `/Volumes` 를 건드리지 않으므로 다른 실제 볼륨과 절대 충돌하지 않는다.
        guard run("/usr/bin/hdiutil", [
            "attach", "-nobrowse", "-noverify", "-noautoopen",
            "-mountpoint", mountDir, "-quiet", imagePath,
        ]) else {
            try? FileManager.default.removeItem(atPath: imagePath)
            return nil
        }

        return HFSPlusTestVolume(mountPoint: PathBytes(mountDir), imagePath: imagePath)
    }

    /// 마운트 해제와 이미지 삭제. 실패해도 조용히 넘어간다 — 정리 코드에서 assert 로
    /// 새 실패를 만들지 않기 위해서다. 호출부는 반드시 `defer` 로 불러서, 검증
    /// 실패로 테스트가 일찍 끝나도 볼륨이 마운트된 채 남지 않게 한다.
    func detach() {
        guard isAttached else { return }
        isAttached = false
        _ = Self.run("/usr/bin/hdiutil", ["detach", mountPoint.displayString, "-force", "-quiet"])
        try? FileManager.default.removeItem(atPath: imagePath)
    }

    @discardableResult
    private static func run(_ executablePath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
