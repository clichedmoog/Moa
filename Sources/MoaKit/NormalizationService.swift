import Foundation

public struct NormalizationPreview: Sendable {
    /// 실제로 이름이 바뀔 항목 수. 확인창 임계값 판단에 쓴다.
    public let targetCount: Int
    /// 순회한 전체 항목 수. 표시용.
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

        var warning: String?
        if let first = roots.first, let info = VolumeInspector.inspect(first),
           !info.preservesNormalization {
            warning = """
                이 볼륨(\(info.fileSystemName))은 파일명을 자동으로 자소분리 형태로 되돌립니다. \
                이름을 바꿔도 유지되지 않으니, 압축해서 옮기는 방법을 쓰세요.
                """
        }

        return NormalizationPreview(targetCount: targets.count,
                                    totalCount: walk.items.count,
                                    volumeWarning: warning,
                                    walk: walk)
    }

    /// 변환을 실행한다. `walk.items` 는 bottom-up 정렬돼 있으므로 순서대로 처리하면 된다.
    public static func run(preview: NormalizationPreview) -> MoaReport {
        var renamed: [ReportEntry] = []
        var alreadyNormalized = 0
        var skipped: [ReportEntry] = []
        var failed: [ReportEntry] = []

        for item in preview.walk.items {
            let display = item.path.displayString
            switch Renamer.normalizeName(at: item.path) {
            case .renamed:
                let newName = Normalizer.normalized(item.path.lastComponent)
                renamed.append(ReportEntry(path: display,
                                           detail: String(decoding: newName, as: UTF8.self)))
            case .alreadyNormalized:
                alreadyNormalized += 1
            case .skippedCollision:
                skipped.append(ReportEntry(path: display, detail: "같은 이름의 다른 파일이 있어 건너뜀"))
            case .verificationFailed:
                failed.append(ReportEntry(path: display, detail: "이 볼륨이 이름을 되돌림"))
            case .failed(let code):
                failed.append(ReportEntry(path: display, detail: message(for: code)))
            }
        }

        for item in preview.walk.skipped {
            let display = item.path.displayString
            switch item.reason {
            case .symlink: skipped.append(ReportEntry(path: display, detail: "심볼릭 링크 — 내부는 건드리지 않음"))
            case .bundle:  skipped.append(ReportEntry(path: display, detail: "번들 — 내부는 건드리지 않음"))
            case .hidden:  skipped.append(ReportEntry(path: display, detail: "숨김 항목"))
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
