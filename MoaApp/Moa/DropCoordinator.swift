import AppKit
import Foundation
import MoaKit
import UniformTypeIdentifiers

enum CoordinatorState: Sendable {
    case idle
    /// 변환 대상이 임계값을 넘어 사용자 확인을 기다리는 중.
    case confirming(NormalizationPreview)
    /// 진행 중 화면에 보여줄 문구. 오래 걸리는 작업이 멈춘 것처럼 보이지 않도록
    /// 무엇이 처리되고 있는지 말해준다.
    case working(String)
    case finished(MoaReport)
    case zipped(ZipResult, URL)
    case failed(String)
}

@MainActor
final class DropCoordinator: ObservableObject {

    /// 이 개수를 넘으면 한 번 확인한다. 상위 폴더를 잘못 드롭하는 사고를 막는 유일한 장치다.
    /// 기준은 순회한 전체가 아니라 **실제 변환 대상** 개수다.
    static let confirmationThreshold = 500

    @Published private(set) var state: CoordinatorState = .idle

    /// `state`가 `.idle`이 아닐 때 들어온 드롭을 미뤄 둔다.
    ///
    /// Dock 아이콘은 어떤 상태에서든 열려 있다 — `DropView`가 `.idle`에서만
    /// 보이는 것과 달리 뷰 계층의 보호를 받지 못한다. 그래서 진입점(`handle`,
    /// `makeZip`, `cleanArchive`) 각각이 자기 앞단에서 idle 여부를 확인하고,
    /// 아니라면 여기 쌓아 둔다. 각 케이스는 그 진입점을 **나중에 그대로 다시
    /// 부르는 데** 필요한 값만 담는다 — 큐에 넣는 시점에 "이게 압축 요청인지
    /// 그냥 정리 요청인지" 미리 판단하지 않는다. 판단은 항상 idle로 돌아온 뒤
    /// 그 진입점 자신이 다시 한다. 배열 하나로 뭉뚱그리면(단순 URL 목록) ZIP
    /// 만들기 요청이 그냥 이름 정리 요청으로 둔갑해버릴 수 있어 타입을 나눴다.
    @Published private var pendingDrops: [PendingDrop] = []

    /// 결과 화면에서 "대기 중인 항목 N개"를 보여주기 위한 값.
    var pendingCount: Int { pendingDrops.count }

    private enum PendingDrop {
        case dropped([URL])
        case zip(from: [URL], to: URL)
        case archive(URL)
    }

    func handle(urls: [URL]) {
        guard !urls.isEmpty else { return }

        // 이미 뭔가 진행 중이거나(working), 확인을 기다리거나(confirming),
        // 아직 사용자가 보지 않은 결과 화면이 떠 있다면(finished/zipped/failed)
        // 지금 바로 처리하지 않는다. 여기서 바로 처리해버리면 working 중엔
        // Task 가 두 개 겹쳐 나중 것이 먼저 것을 덮어쓰고, 결과 화면 위에서는
        // 아직 읽지 않은 리포트가 조용히 사라진다 — 실패 목록이 사라지는 쪽이
        // 더 나쁘다.
        guard case .idle = state else {
            pendingDrops.append(.dropped(urls))
            return
        }

        // .zip 을 드롭하면 정리 모드로 간다.
        if urls.count == 1, urls[0].pathExtension.lowercased() == "zip" {
            cleanArchive(at: urls[0])
            return
        }

        let roots = urls.map { PathBytes(Array($0.path.utf8)) }
        let preview = NormalizationService.preview(roots: roots)

        if preview.targetCount > Self.confirmationThreshold {
            state = .confirming(preview)
        } else {
            execute(preview)
        }
    }

    func confirm(_ preview: NormalizationPreview) {
        execute(preview)
    }

    func cancel() {
        returnToIdle()
    }

    func reset() {
        returnToIdle()
    }

    /// 드롭된 항목을 NFC 이름의 ZIP 으로 묶는다.
    func makeZip(from urls: [URL], to destination: URL) {
        guard case .idle = state else {
            pendingDrops.append(.zip(from: urls, to: destination))
            return
        }
        let roots = urls.map { PathBytes(Array($0.path.utf8)) }
        state = .working("압축하는 중")
        Task {
            let next = await Self.buildZip(roots: roots, destination: destination)
            self.state = next
        }
    }

    /// idle로 돌아가면서, 그 사이 밀린 드롭이 있으면 맨 앞의 것부터 원래 진입점을
    /// 통해 그대로 다시 부른다. `cancel()`/`reset()`에서만 부른다 — 즉 사용자가
    /// 확인 대화상자를 취소하거나 결과 화면의 "확인"을 눌러 **직접 그 화면을
    /// 치운** 시점에만 다음 대기 작업이 시작된다. 자동으로 넘어가지 않는다.
    private func returnToIdle() {
        state = .idle
        guard !pendingDrops.isEmpty else { return }
        let next = pendingDrops.removeFirst()
        switch next {
        case .dropped(let urls):
            handle(urls: urls)
        case .zip(let from, let to):
            makeZip(from: from, to: to)
        case .archive(let url):
            cleanArchive(at: url)
        }
    }

    private func execute(_ preview: NormalizationPreview) {
        // targetCount 를 쓴다 — ConfirmView 가 보여준 숫자와 같은 숫자라야
        // "확인창에서 본 개수"와 "지금 처리 중인 개수"가 사용자 눈에 다르게 안 보인다.
        // 앱의 어휘(모으다)를 따른다 — 버튼·진행 문구·결과 문구가 같은 동사를 쓴다.
        state = .working("\(preview.targetCount)개를 모으는 중")
        Task {
            let report = await Self.runOffMain(preview)
            self.state = .finished(report)
        }
    }

    /// 정리된 ZIP 의 저장 위치는 **반드시 저장 패널로 사용자에게 묻는다.**
    ///
    /// 샌드박스 실측(스펙 10.2)에서 드롭된 항목의 부모 디렉터리에 파일을 만들려 하자
    /// `EPERM` 으로 거부됐다. 샌드박스가 권한을 주는 대상은 드롭된 항목 자신이지
    /// 그 부모가 아니다. 사용자가 저장 패널에서 고른 경로에는 권한이 부여되므로
    /// 이 경로만이 확실히 동작한다.
    private func cleanArchive(at url: URL) {
        guard case .idle = state else {
            pendingDrops.append(.archive(url))
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ZipCleaner.defaultDestination(for: url).lastPathComponent
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else {
            returnToIdle()
            return
        }
        state = .working("압축 파일을 정리하는 중")
        Task {
            let next = await Self.cleanOffMain(source: url, destination: destination)
            self.state = next
        }
    }

    // MARK: - 메인 스레드 밖에서 도는 작업
    //
    // `nonisolated` 정적 함수로 두면 @MainActor 인 self 를 백그라운드로 넘기지 않아도 되고,
    // Swift 6 의 엄격한 동시성 검사에서도 문제가 생기지 않는다.
    // 주고받는 값(PathBytes, URL, MoaReport, ZipResult)은 모두 Sendable 이다.

    private nonisolated static func runOffMain(_ preview: NormalizationPreview) async -> MoaReport {
        await Task.detached(priority: .userInitiated) {
            NormalizationService.run(preview: preview)
        }.value
    }

    private nonisolated static func buildZip(roots: [PathBytes],
                                             destination: URL) async -> CoordinatorState {
        await Task.detached(priority: .userInitiated) {
            do {
                return .zipped(try ZipWriter.write(roots: roots, to: destination), destination)
            } catch {
                return .failed("압축 파일을 만들지 못했습니다")
            }
        }.value
    }

    private nonisolated static func cleanOffMain(source: URL,
                                                 destination: URL) async -> CoordinatorState {
        await Task.detached(priority: .userInitiated) {
            do {
                return .zipped(try ZipCleaner.clean(archiveAt: source, to: destination), destination)
            } catch {
                return .failed("압축 파일을 읽을 수 없습니다")
            }
        }.value
    }
}
