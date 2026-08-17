import Foundation

public struct ReportEntry: Equatable, Sendable {
    public let path: String
    public let detail: String
    /// 고쳐야 했는데 못 고친 항목인가.
    ///
    /// `skipped` 안에는 성격이 다른 두 가지가 섞인다 — 심볼릭 링크·번들·숨김처럼
    /// **애초에 대상이 아니었던 것**과, 이름 충돌처럼 **대상이었는데 손대지 못한 것**이다.
    /// 앞의 것은 "이미 다 정상"이라고 말해도 참이지만 뒤의 것은 거짓이 된다.
    /// 문구를 문자열로 비교해 구분하면 문구가 바뀌는 순간 조용히 깨지므로 값으로 남긴다.
    public let leftUnfixed: Bool

    public init(path: String, detail: String, leftUnfixed: Bool = false) {
        self.path = path
        self.detail = detail
        self.leftUnfixed = leftUnfixed
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

    /// 고쳐야 했는데 못 고친 항목이 있는가.
    ///
    /// `failed` 뿐 아니라 **이름 충돌로 건너뛴 것**도 포함한다. 충돌은 의도적 제외처럼
    /// 보이지만 실제로는 고쳐야 할 파일이 그대로 남은 것이라, "이미 다 정상이다"라고
    /// 말하면 거짓이 된다.
    public var hasUnfixed: Bool {
        !failed.isEmpty || skipped.contains(where: \.leftUnfixed)
    }
}
