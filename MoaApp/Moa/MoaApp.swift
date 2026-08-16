import AppKit
import MoaKit
import SwiftUI

@main
struct MoaApp: App {
    @StateObject private var coordinator = DropCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
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
                ProgressView(message)
                    .frame(minWidth: 420, minHeight: 320)
                    .transition(.opacity)

            case .finished(let report):
                ResultView(report: report) { coordinator.reset() }
                    .transition(.opacity)

            case .zipped(let result, let url):
                ZippedView(result: result, url: url) { coordinator.reset() }
                    .transition(.opacity)

            case .failed(let message):
                FailedView(message: message) { coordinator.reset() }
                    .transition(.opacity)
            }
        }
        // 상태 전환마다 화면이 뚝뚝 끊기지 않도록 짧게 크로스페이드한다.
        // 유틸리티 앱이라 과하지 않게, 그리고 Reduce Motion 이 켜져 있으면
        // 아예 즉시 바뀌게 한다.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: stateTag)
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
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("\(result.entryCount)개 항목을 묶었습니다")
                .font(.title3.bold())

            if !result.failed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(result.failureCount)개 항목을 읽지 못해 빠졌습니다",
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
                DisclosureGroup("제외한 항목 \(result.omitted.count)개") {
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
                }
                .font(.subheadline)
            }

            Button("Finder에서 보기") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("확인", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 320)
    }
}

private struct FailedView: View {
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text(message)
            Button("확인", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 320)
    }
}
