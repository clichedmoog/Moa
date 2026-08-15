import XCTest
@testable import MoaKit

final class VolumeInspectorTests: XCTestCase {

    func testDetectsAPFSOnTempDir() throws {
        let dir = TestSupport.makeTempDir()
        defer { TestSupport.remove(dir) }

        let info = try XCTUnwrap(VolumeInspector.inspect(dir))
        XCTAssertEqual(info.fileSystemName, "apfs")
        XCTAssertTrue(info.preservesNormalization)
    }

    func testReturnsNilForMissingPath() {
        XCTAssertNil(VolumeInspector.inspect(PathBytes("/이런경로는없다/절대로")))
    }

    func testKnownNFDForcingFileSystems() {
        for name in ["hfs", "exfat", "msdos", "smbfs"] {
            XCTAssertFalse(VolumeInspector.preservesNormalization(fileSystemName: name),
                           "\(name) 은 NFD 를 강제한다")
        }
    }

    func testAPFSPreservesNormalization() {
        XCTAssertTrue(VolumeInspector.preservesNormalization(fileSystemName: "apfs"))
    }

    /// 모르는 파일시스템은 낙관적으로 본다.
    /// 실제 판정은 Renamer 의 사후 검증이 하므로 여기서 막을 필요가 없다.
    func testUnknownFileSystemIsAssumedPreserving() {
        XCTAssertTrue(VolumeInspector.preservesNormalization(fileSystemName: "someexoticfs"))
    }
}
