import Foundation

/// 파일명의 유니코드 정규화 형태를 판단하고 변환한다.
public enum Normalizer {

    /// 이 이름이 NFC 로 바뀌어야 하는가.
    ///
    /// 판단은 반드시 **바이트열 비교**로 한다. `String ==` 는 정규화를 무시하므로
    /// `name == name.precomposedStringWithCanonicalMapping` 은 항상 `true` 가 되어
    /// 아무것도 변환되지 않는다.
    public static func needsNormalization(_ name: [UInt8]) -> Bool {
        guard let text = String(bytes: name, encoding: .utf8) else { return false }
        return Array(text.precomposedStringWithCanonicalMapping.utf8) != name
    }

    /// NFC(모아쓰기)로 정규화한 이름.
    ///
    /// 한글에만 적용하지 않고 모든 문자에 적용한다. 일본어 탁점, 라틴 악센트도
    /// 같은 문제를 겪으며 canonical mapping 이라 의미가 보존된다.
    /// 유효한 UTF-8 이 아니면 손대지 않는다.
    public static func normalized(_ name: [UInt8]) -> [UInt8] {
        guard let text = String(bytes: name, encoding: .utf8) else { return name }
        return Array(text.precomposedStringWithCanonicalMapping.utf8)
    }
}
