import Foundation

public struct ReportEntry: Equatable, Sendable {
    public let path: String
    public let detail: String

    public init(path: String, detail: String) {
        self.path = path
        self.detail = detail
    }
}

/// 처리 결과. 사용자에게 4가지로 나눠 보여준다.
public struct MoaReport: Sendable {
    /// 이름을 바꾸고 디스크에서 확인까지 마친 항목.
    public let renamed: [ReportEntry]
    /// 처음부터 NFC 라 건드리지 않은 항목 수. 수정 시각이 보존된다.
    public let alreadyNormalized: Int
    /// 의도적으로 제외한 항목 — 충돌, 번들 내부, 심볼릭 링크, 숨김.
    public let skipped: [ReportEntry]
    /// 권한 부족, 검증 실패 등.
    public let failed: [ReportEntry]
    /// NFD 를 강제하는 볼륨일 때의 안내 문구.
    public let volumeWarning: String?

    public var hasChanges: Bool { !renamed.isEmpty }
}
