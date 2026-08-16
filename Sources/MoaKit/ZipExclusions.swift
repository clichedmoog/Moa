import Foundation

/// 윈도우에서 풀었을 때 쓸모없는 맥 전용 파일을 걸러낸다.
public enum ZipExclusions {

    private static let exactNames: Set<[UInt8]> = [
        Array(".DS_Store".utf8),
        Array(".Spotlight-V100".utf8),
        Array(".Trashes".utf8),
        Array(".fseventsd".utf8),
        Array(".TemporaryItems".utf8),
        Array(".apdisk".utf8),
        Array("__MACOSX".utf8)
    ]

    /// AppleDouble 리소스 포크 사이드카.
    private static let appleDoublePrefix = Array("._".utf8)

    public static func shouldExclude(name: [UInt8]) -> Bool {
        if exactNames.contains(name) { return true }
        return name.starts(with: appleDoublePrefix)
    }
}
