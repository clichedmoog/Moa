import Foundation

public struct NormalizationPreview: Sendable {
    /// 실제로 이름이 바뀔 항목 수. 확인창 임계값 판단에 쓴다.
    public let targetCount: Int
    /// 순회한 전체 항목 수 — 처리 대상 + 건너뜀 + 실패. 표시용.
    public let totalCount: Int
    public let volumeWarning: String?
    public let walk: WalkResult
}

/// 이름 변환 파이프라인을 조립한다.
public enum NormalizationService {

    /// 실행 전에 대상을 파악한다. 앱은 이 결과로 확인창 표시 여부를 정한다.
    public static func preview(roots: [PathBytes]) -> NormalizationPreview {
        let walk = TreeWalker.collect(from: roots)
        let targets = walk.items.filter { Normalizer.needsNormalization($0.path.lastComponent) }

        return NormalizationPreview(targetCount: targets.count,
                                    // "전체 N개 항목을 확인했습니다" 의 N. items 만 세면
                                    // 번들·숨김·심볼릭 링크로 건너뛰거나 권한 문제로 보지
                                    // 못한 항목이 빠져 사용자가 본 것보다 적게 표시된다.
                                    totalCount: walk.items.count + walk.skipped.count + walk.failures.count,
                                    volumeWarning: volumeWarning(for: roots),
                                    walk: walk)
    }

    /// 대상 루트들 가운데 정규화를 보존하지 않는 볼륨을 모두 찾아 이름을 나열한
    /// 경고문을 만든다. `roots.first` 만 보면 두 번째 이후 루트의 볼륨을 놓친다 —
    /// 여러 볼륨에 걸친 드롭에서 그 경고가 가장 필요하다.
    private static func volumeWarning(for roots: [PathBytes]) -> String? {
        var seen = Set<String>()
        var names: [String] = []
        for root in roots {
            guard let info = VolumeInspector.inspect(root), !info.preservesNormalization else { continue }
            if seen.insert(info.fileSystemName).inserted {
                names.append(info.fileSystemName)
            }
        }
        guard !names.isEmpty else { return nil }

        let joined = names.joined(separator: ", ")
        return """
            이 볼륨(\(joined))은 파일명을 자동으로 자소분리 형태로 되돌립니다. \
            이름을 바꿔도 유지되지 않으니, 압축해서 옮기는 방법을 쓰세요.
            """
    }

    /// 변환을 실행한다. `walk.items` 는 bottom-up 정렬돼 있으므로 순서대로 처리하면 된다.
    public static func run(preview: NormalizationPreview) -> MoaReport {
        var renamed: [ReportEntry] = []
        var alreadyNormalized = 0
        var skipped: [ReportEntry] = []
        var failed: [ReportEntry] = []

        // 심볼릭 링크·번들은 TreeWalker 가 같은 경로를 items 와 skipped 양쪽에 올린다
        // (링크·번들 자신의 이름은 바뀌지만 안쪽으로는 내려가지 않으므로 둘 다 맞는
        // 사실이다). 그 경로가 실제로 이름을 바꿨다면 여기서 인덱스를 기억해뒀다가,
        // skipped 를 훑을 때 "건너뜀" 을 별도 줄로 만들지 않고 이 줄의 detail 에
        // 덧붙인다 — 같은 경로가 "변환됨"과 "건너뜀"으로 동시에, 모순되게 보이면 안
        // 된다. 바이트 단위인 PathBytes 를 키로 써서 비교한다 (String 비교 금지).
        var renamedIndexByPath: [PathBytes: Int] = [:]

        for item in preview.walk.items {
            let display = item.path.displayString
            switch Renamer.normalizeName(at: item.path) {
            case .renamed:
                let newName = Normalizer.normalized(item.path.lastComponent)
                renamedIndexByPath[item.path] = renamed.count
                renamed.append(ReportEntry(path: display,
                                           detail: String(decoding: newName, as: UTF8.self)))
            case .alreadyNormalized:
                alreadyNormalized += 1
            case .skippedCollision:
                // 충돌은 "건너뜀"에 들어가지만 성격이 다르다 — 고쳐야 할 파일이 그대로 남았다.
                skipped.append(ReportEntry(path: display,
                                           detail: "같은 이름의 다른 파일이 있어 건너뜀",
                                           leftUnfixed: true))
            case .verificationFailed:
                failed.append(ReportEntry(path: display, detail: "이 볼륨이 이름을 되돌림"))
            case .failed(let code):
                failed.append(ReportEntry(path: display, detail: message(for: code)))
            }
        }

        for item in preview.walk.skipped {
            let display = item.path.displayString
            switch item.reason {
            case .symlink, .bundle:
                let label = item.reason == .symlink ? "심볼릭 링크" : "번들"
                if let index = renamedIndexByPath[item.path] {
                    let existing = renamed[index]
                    renamed[index] = ReportEntry(path: existing.path,
                                                 detail: "\(existing.detail) — 내부는 건드리지 않음")
                } else {
                    skipped.append(ReportEntry(path: display, detail: "\(label) — 내부는 건드리지 않음"))
                }
            case .hidden:
                // 숨김 항목은 애초에 items 에 오르지 않으므로(TreeWalker 가 재귀도
                // 이름 변환도 하지 않는다) renamed 와 겹칠 일이 없다.
                skipped.append(ReportEntry(path: display, detail: "숨김 항목"))
            }
        }

        // 순회 중 보지 못한 것은 "건너뜀"이 아니라 "실패"다.
        // 의도적 제외와 섞으면 사용자가 "USB 를 읽지 못했다"를
        // ".git 을 건너뛰었다" 사이에서 놓친다.
        for failure in preview.walk.failures {
            let display = failure.path.displayString
            switch failure.reason {
            case .unreadableDirectory:
                failed.append(ReportEntry(path: display,
                                          detail: "폴더를 읽지 못해 안쪽을 확인하지 못함 — \(message(for: failure.errno))"))
            case .inaccessible:
                failed.append(ReportEntry(path: display,
                                          detail: "항목에 접근하지 못함 — \(message(for: failure.errno))"))
            }
        }

        return MoaReport(renamed: renamed,
                         alreadyNormalized: alreadyNormalized,
                         skipped: skipped,
                         failed: failed,
                         volumeWarning: preview.volumeWarning)
    }

    private static func message(for code: Int32) -> String {
        switch code {
        case EACCES, EPERM: return "권한이 없습니다"
        case ENOENT:        return "파일을 찾을 수 없습니다"
        case EROFS:         return "읽기 전용 볼륨입니다"
        default:            return "실패 (errno \(code))"
        }
    }
}
