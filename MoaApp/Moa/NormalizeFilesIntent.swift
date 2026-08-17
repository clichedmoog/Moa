import AppIntents
import Foundation
import MoaKit

/// 단축어에서 부를 수 있는 액션. 사용자가 자기 워크플로 안에 이름 고치기를 끼워 넣을 수 있게 한다.
///
/// 우클릭 서비스(`ServicesProvider`)와 목적은 같지만 쓰임이 다르다. 서비스는 지금 이 파일을
/// 한 번 고치는 것이고, 단축어는 "다운로드 폴더를 훑어서 고친 다음 압축한다" 같은 조합을
/// 사용자가 직접 짜게 해준다.
///
/// **`supportedContentTypes:` 를 쓰지 않는 이유.** 그 인자는 macOS 15 부터라, 넣으면
/// 배포 타깃을 13.0 에서 올려야 하고 Ventura·Sonoma 사용자가 잘린다. 그 인자가 하는 일은
/// 파일 선택기에서 고를 수 있는 타입을 좁히는 것뿐인데, 모아는 어차피 모든 파일을 받으므로
/// 좁힐 것이 없다. 없애는 쪽이 손해가 없다.
///
/// **결과를 UI 로 보내지 않는 이유.** 단축어는 창 없이 도는 게 보통이고, 여러 항목을 반복
/// 처리하는 중에 창이 튀어나오면 방해가 된다. 대신 처리 결과를 돌려주므로 사용자가
/// 다음 액션에서 쓸 수 있다.
struct NormalizeFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "파일명 모아쓰기"
    static var description = IntentDescription(
        "자소분리된 한글 파일명을 모아쓰기(NFC)로 되돌립니다. 폴더를 주면 안쪽까지 훑습니다.",
        categoryName: "파일"
    )

    /// 창을 띄우지 않는다. 단축어 안에서 조용히 돌아야 한다.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "파일")
    var files: [IntentFile]

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let roots: [PathBytes] = files.compactMap { file in
            // 원본 파일에 대한 참조가 있어야 제자리에서 이름을 고칠 수 있다.
            // 단축어가 데이터 복사본만 넘기면 fileURL 이 nil 이고, 그때는 고칠 대상이 없다 —
            // 임시 복사본의 이름을 바꿔봐야 사용자 파일은 그대로다.
            guard let url = file.fileURL else { return nil }
            return PathBytes(Self.fileSystemBytes(of: url))
        }

        guard !roots.isEmpty else {
            throw NormalizeFilesError.noOriginalFiles
        }

        // 메인 스레드 밖에서 돈다. 훑기와 rename 은 항목 수에 비례해 오래 걸리는데,
        // 여기서 그대로 돌리면 앱 창이 떠 있는 동안 그만큼 멈춘다.
        // `DropCoordinator` 가 같은 이유로 같은 선택을 했다.
        let report = await Task.detached(priority: .userInitiated) {
            let preview = NormalizationService.preview(roots: roots)
            return NormalizationService.run(preview: preview)
        }.value

        return .result(value: report.renamed.count)
    }

    /// `URL.path` 는 정규화된 Swift 문자열을 거치면서 경로를 되돌려 놓을 수 있다.
    /// 파일시스템이 실제로 갖고 있는 바이트를 그대로 가져온다.
    private static func fileSystemBytes(of url: URL) -> [UInt8] {
        url.withUnsafeFileSystemRepresentation { rep -> [UInt8] in
            guard let rep else { return [] }
            let raw = UnsafeRawPointer(rep).assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: raw, count: strlen(rep)))
        }
    }
}

enum NormalizeFilesError: Error, CustomLocalizedStringResourceConvertible {
    case noOriginalFiles

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noOriginalFiles:
            // 사용자가 고칠 수 있는 문제다. 파일 자체가 아니라 사본이 넘어온 상황이므로,
            // 무엇을 바꿔야 하는지 알려준다.
            "원본 파일을 받지 못했습니다. 앞 단계에서 파일 자체를 넘겨주세요."
        }
    }
}
