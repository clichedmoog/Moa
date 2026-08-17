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
        // 원본 파일에 대한 참조가 있어야 제자리에서 이름을 고칠 수 있다.
        // 단축어가 데이터 복사본만 넘기면 `fileURL` 이 nil 이고, 그때는 고칠 대상이 없다 —
        // 임시 복사본의 이름을 바꿔봐야 사용자 파일은 그대로다.
        //
        // **닿지 못한 게 하나라도 있으면 전부 멈춘다.** 닿은 것만 골라 처리하면
        // 반환값은 "3개 고침"인데 사용자는 5개를 넘겼으므로, 나머지 2개는 고칠 게
        // 없었다고 읽는다. 단축어는 사람이 지켜보지 않는 자동화라 그 오해가 조용히
        // 쌓인다. 이 저장소가 실패 목록을 절대 삼키지 않는 것과 같은 이유다.
        var roots: [PathBytes] = []
        roots.reserveCapacity(files.count)
        for file in files {
            guard let url = file.fileURL else {
                throw NormalizeFilesError.notAnOriginalFile(name: file.filename)
            }
            let bytes = Self.fileSystemBytes(of: url)
            guard !bytes.isEmpty else {
                throw NormalizeFilesError.notAnOriginalFile(name: file.filename)
            }
            roots.append(PathBytes(bytes))
        }

        guard !roots.isEmpty else {
            throw NormalizeFilesError.noFiles
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
    /// 넘어온 항목이 원본 파일이 아니라 사본이었다.
    case notAnOriginalFile(name: String)
    /// 넘어온 항목이 아예 없다.
    case noFiles

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAnOriginalFile(let name):
            // 사용자가 고칠 수 있는 문제다. 어느 항목이 문제였는지 짚어주지 않으면
            // 여러 파일을 넘긴 단축어에서 무엇을 바꿔야 할지 알 수 없다.
            "‘\(name)’의 원본을 받지 못했습니다. 앞 단계에서 파일 사본이 아니라 파일 자체를 넘겨주세요."
        case .noFiles:
            "고칠 파일이 없습니다."
        }
    }
}
