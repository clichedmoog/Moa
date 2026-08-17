import AppKit
import MoaKit
import SwiftUI

@main
struct MoaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = DropCoordinator()

    var body: some Scene {
        // `WindowGroup` 이 아니라 `Window` 다. 앞의 것은 문서 기반 앱용이라
        // Dock 드롭이나 재실행마다 창을 새로 연다 — 파일 하나를 처리하고 끝나는
        // 유틸리티에는 맞지 않고, 창이 여러 개면 `AppDelegate` 가 붙들 coordinator 가
        // 어느 창의 것인지도 흐려져 대기열이 엉킨다. 창은 언제나 하나다.
        Window("Moa", id: "main") {
            RootView()
                .environmentObject(coordinator)
                .task {
                    appDelegate.coordinator = coordinator
                    appDelegate.flushPending()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var coordinator: DropCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 크로스페이드 애니메이션이 지켜볼 값. `CoordinatorState` 전체를 Equatable 로
    /// 만들 필요 없이 어느 케이스인지만 구분하면 충분하다.
    private var stateTag: Int {
        switch coordinator.state {
        case .idle: return 0
        case .confirming: return 1
        case .working: return 2
        case .finished: return 3
        case .zipped: return 4
        case .failed: return 5
        }
    }

    var body: some View {
        Group {
            switch coordinator.state {
            case .idle:
                DropView()
                    .transition(.opacity)

            case .confirming(let preview):
                ConfirmView(preview: preview,
                            onConfirm: { coordinator.confirm(preview) },
                            onCancel: { coordinator.cancel() })
                    .transition(.opacity)

            case .working(let message):
                WorkingView(message: message)
                    .transition(.opacity)

            case .finished(let report):
                ResultView(report: report, pendingCount: coordinator.pendingCount) { coordinator.reset() }
                    .transition(.opacity)

            case .zipped(let result, let url):
                ZippedView(result: result, url: url, pendingCount: coordinator.pendingCount) { coordinator.reset() }
                    .transition(.opacity)

            case .failed(let message):
                FailedView(message: message, pendingCount: coordinator.pendingCount) { coordinator.reset() }
                    .transition(.opacity)
            }
        }
        // 상태 전환마다 화면이 뚝뚝 끊기지 않도록 짧게 크로스페이드한다.
        // 유틸리티 앱이라 과하지 않게, 그리고 Reduce Motion 이 켜져 있으면
        // 아예 즉시 바뀌게 한다.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: stateTag)
    }
}

/// `.working` 상태 화면. 서명 요소를 "모으는 중" 위치에 두고, 아래에 무엇이
/// 처리되는지 말로 덧붙인다 — 빈 스피너만으로는 오래 걸리는 작업이 멈춘 것처럼
/// 보인다.
private struct WorkingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            GatherMark(phase: .gathering)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 320)
    }
}

/// `.zipped` 상태 화면.
///
/// `omitted` 는 흔한 일(`.DS_Store` 등)이라 접어두지만, `failed` (읽지 못해
/// 아예 빠진 항목)는 절대 숨기지 않는다 — 모른 채 USB 로 옮기면 파일이
/// 사라진 줄도 모른다.
private struct ZippedView: View {
    let result: ZipResult
    let url: URL
    /// 이 결과를 보는 동안 Dock 등으로 더 들어와 뒤에서 기다리고 있는 항목 수.
    let pendingCount: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // 결과 화면이므로 자모 마크가 아니라 완료 표시를 쓴다.
            DoneMark(outcome: result.failed.isEmpty ? .changed : .hadFailures)
            Text("\(result.entryCount)개를 모았습니다")
                .font(.title3.bold())

            if !result.failed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(result.failureCount)개는 모으지 못했습니다",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)

                    ForEach(Array(result.failed.prefix(50).enumerated()), id: \.offset) { _, entry in
                        Text("\((entry.path as NSString).lastPathComponent) — \(entry.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if result.failed.count > 50 {
                        Text("외 \(result.failed.count - 50)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // `omitted` 에는 맥 전용 파일뿐 아니라 심볼릭 링크·번들·특수 파일도
            // 들어온다. 문구를 "맥 전용 파일"로 좁히면 거짓말이 된다.
            if !result.omitted.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(result.omitted.prefix(50).enumerated()), id: \.offset) { _, entry in
                            Text("\((entry.path as NSString).lastPathComponent) — \(entry.detail)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if result.omitted.count > 50 {
                            Text("외 \(result.omitted.count - 50)개")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Label("제외한 항목 \(result.omitted.count)개", systemImage: "minus.circle")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            }

            Button("Finder에서 보기") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            if pendingCount > 0 {
                Text("대기 중인 항목 \(pendingCount)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(pendingCount > 0 ? "확인하고 다음 처리" : "확인", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 320)
    }
}

private struct FailedView: View {
    let message: String
    /// 이 결과를 보는 동안 Dock 등으로 더 들어와 뒤에서 기다리고 있는 항목 수.
    let pendingCount: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text(message)
            if pendingCount > 0 {
                Text("대기 중인 항목 \(pendingCount)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(pendingCount > 0 ? "확인하고 다음 처리" : "확인", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 320)
    }
}
