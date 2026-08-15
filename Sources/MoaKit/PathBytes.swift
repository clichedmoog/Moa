import Foundation

/// 파일시스템 경로를 UTF-8 바이트열로 다루는 값 타입.
///
/// `String` 을 쓰지 않는 이유는 두 가지다.
/// 1. 파일시스템 이름은 유효한 UTF-8 이 아닐 수 있고, `String` 왕복은 그런 이름을 손상시킨다.
/// 2. `String` 을 경로로 받는 Foundation API 는 `NSString.fileSystemRepresentation` 을 거치며
///    경로를 NFD 로 변환한다. NFC 로 이름을 바꾸려는 이 앱에서는 치명적이다.
public struct PathBytes: Equatable, Hashable, Sendable {

    /// NUL 종료 문자를 포함하지 않는 경로 바이트열.
    public let bytes: [UInt8]

    private static let separator = UInt8(ascii: "/")

    /// 후행 구분자를 제거해 정규화한다. 경로가 정확히 `/` 뿐이면 그대로 둔다.
    /// 내부(중간)의 바이트는 절대 건드리지 않는다 — 손상된 UTF-8 이나 내부의
    /// 중복 구분자도 그대로 보존된다.
    private static func canonicalize(_ bytes: [UInt8]) -> [UInt8] {
        var end = bytes.count
        while end > 1 && bytes[end - 1] == separator {
            end -= 1
        }
        return Array(bytes[..<end])
    }

    /// 후행 구분자를 제거해 정규화한다 (경로가 정확히 `/` 뿐이면 예외).
    public init(_ bytes: [UInt8]) {
        self.bytes = Self.canonicalize(bytes)
    }

    /// 후행 구분자를 제거해 정규화한다 (경로가 정확히 `/` 뿐이면 예외).
    public init(_ string: String) {
        self.bytes = Self.canonicalize(Array(string.utf8))
    }

    /// 구분자 중복 없이 경로 요소를 잇는다. 빈 경로에 이어붙일 때는
    /// 선행 구분자를 넣지 않는다.
    public func appending(_ component: [UInt8]) -> PathBytes {
        var result = bytes
        if !result.isEmpty && result.last != Self.separator {
            result.append(Self.separator)
        }
        result.append(contentsOf: component)
        return PathBytes(result)
    }

    /// 마지막 경로 요소. 경로가 비었거나 `/` 뿐이면 빈 배열.
    public var lastComponent: [UInt8] {
        guard let index = bytes.lastIndex(of: Self.separator) else { return bytes }
        return Array(bytes[bytes.index(after: index)...])
    }

    /// 마지막 요소를 제거한 상위 경로. 루트에서는 `/` 를 유지한다.
    public func removingLastComponent() -> PathBytes {
        guard let index = bytes.lastIndex(of: Self.separator) else { return PathBytes([]) }
        if index == bytes.startIndex { return PathBytes([Self.separator]) }
        return PathBytes(Array(bytes[..<index]))
    }

    /// 유효한 UTF-8 일 때만 문자열을 돌려준다. 손실 변환을 하지 않는다.
    public var utf8String: String? {
        String(bytes: bytes, encoding: .utf8)
    }

    /// 표시용 문자열. 유효하지 않은 바이트는 대체 문자로 바뀐다.
    public var displayString: String {
        utf8String ?? String(decoding: bytes, as: UTF8.self)
    }

    /// NUL 을 붙여 C 문자열로 넘긴다.
    public func withCString<R>(_ body: (UnsafePointer<CChar>) throws -> R) rethrows -> R {
        var buffer = bytes.map { CChar(bitPattern: $0) }
        buffer.append(0)
        return try buffer.withUnsafeBufferPointer { try body($0.baseAddress!) }
    }
}
