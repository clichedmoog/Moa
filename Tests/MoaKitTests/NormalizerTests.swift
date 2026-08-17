import XCTest
@testable import MoaKit

final class NormalizerTests: XCTestCase {

    func testNFDNeedsNormalization() {
        XCTAssertTrue(Normalizer.needsNormalization(TestSupport.nfd("한글.txt")))
    }

    func testNFCDoesNotNeedNormalization() {
        XCTAssertFalse(Normalizer.needsNormalization(TestSupport.nfc("한글.txt")))
    }

    func testASCIIDoesNotNeedNormalization() {
        XCTAssertFalse(Normalizer.needsNormalization(Array("report.txt".utf8)))
    }

    /// 한글만의 문제가 아니다. 일본어 탁점도 같은 방식으로 분해된다.
    func testJapaneseDakutenNeedsNormalization() {
        XCTAssertTrue(Normalizer.needsNormalization(TestSupport.nfd("がっこう.txt")))
    }

    /// 라틴 악센트도 마찬가지다.
    func testLatinAccentNeedsNormalization() {
        XCTAssertTrue(Normalizer.needsNormalization(TestSupport.nfd("café.txt")))
    }

    func testNormalizedProducesNFCBytes() {
        let result = Normalizer.normalized(TestSupport.nfd("한.txt"))
        XCTAssertEqual(result, [0xED, 0x95, 0x9C, 0x2E, 0x74, 0x78, 0x74])
    }

    func testNormalizedIsIdempotent() {
        let once = Normalizer.normalized(TestSupport.nfd("한글.txt"))
        XCTAssertEqual(Normalizer.normalized(once), once)
    }

    /// 유효하지 않은 UTF-8 은 손대지 않고 그대로 돌려준다.
    func testInvalidUTF8IsLeftAlone() {
        let broken: [UInt8] = [0xFF, 0xFE, 0x41]
        XCTAssertFalse(Normalizer.needsNormalization(broken))
        XCTAssertEqual(Normalizer.normalized(broken), broken)
    }

    /// 이 테스트는 String == 로 구현했을 때 반드시 실패한다.
    /// Swift 의 String 비교는 정규화를 무시하므로 두 문자열이 "같다"고 판정된다.
    func testStringComparisonWouldBeWrong() {
        let nfdString = "한.txt".decomposedStringWithCanonicalMapping
        XCTAssertTrue(nfdString == nfdString.precomposedStringWithCanonicalMapping,
                      "String == 는 정규화를 무시한다. 이 성질 때문에 스칼라 비교가 필요하다")
        XCTAssertTrue(Normalizer.needsNormalization(Array(nfdString.utf8)),
                      "바이트로 보면 분명히 다르다")
    }
}
