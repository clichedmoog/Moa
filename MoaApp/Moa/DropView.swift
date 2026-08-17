import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DropView: View {
    @EnvironmentObject var coordinator: DropCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    @State private var isHovering = false

    private var gatherPhase: GatherMark.Phase { isTargeted ? .leaning : .scattered }

    private var borderAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    var body: some View {
        VStack(spacing: 14) {
            GatherMark(phase: gatherPhase)

            Text("여기에 놓으세요")
                .font(.headline)

            Text("흩어진 자모를 모아씁니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // 드롭이 어려운 사용자를 위한, 드래그에 기대지 않는 대안(HIG 요구사항).
            // 항상 자리를 차지하되(opacity/offset 만 바꿔) 호버 시작·종료에
            // 레이아웃이 튀지 않게 한다.
            Button("파일 선택…") { openPanel() }
                .buttonStyle(.borderedProminent)
                .opacity(isHovering ? 1 : 0)
                .offset(y: isHovering ? 0 : 6)
                .allowsHitTesting(isHovering)
                .animation(hoverAnimation, value: isHovering)
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 320)
        // 창 전체가 드롭 영역이다. 안에 또 사각형을 그리지 않는다 —
        // 창이 이미 경계를 갖고 있는데 그 안에 테두리를 하나 더 두면
        // 같은 말을 두 번 하는 셈이고, 요즘 macOS 앱은 그렇게 하지 않는다.
        // 대신 드래그가 들어온 순간에만 배경이 옅게 물들어 여기가 표적임을 알린다.
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accentColor.opacity(isTargeted ? 0.10 : 0))
                .padding(12)
                .animation(borderAnimation, value: isTargeted)
        }
        .onHover { isHovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            coordinator.handle(urls: urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            coordinator.handle(urls: panel.urls)
        }
    }
}
