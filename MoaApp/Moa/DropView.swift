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
        ZStack {
            surface

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
            .padding()
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
        .onHover { isHovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            coordinator.handle(urls: urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    /// 드롭 영역 자체의 표면. macOS 26 이상에서는 Liquid Glass, 그 아래에서는
    /// `.regularMaterial` — 배포 최저 버전(macOS 13)을 올리지 않기 위해 후자를
    /// 항상 지원하고, 전자는 있으면 쓰는 보너스로만 둔다.
    ///
    /// 재질만으로는 창 배경과 경계가 거의 안 보여 옅은 테두리를 하나 더한다 —
    /// 색조는 바꾸지 않고(강조색을 새로 끌어오지 않는다) 드래그가 들어오면
    /// 그저 더 또렷해지기만 한다. "밀도 관계로 표현한다"는 원칙을 테두리에도
    /// 그대로 적용한 것이다.
    @ViewBuilder
    private var surface: some View {
        if #available(macOS 26, *) {
            RoundedRectangle(cornerRadius: 20)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                .overlay(border)
                .animation(borderAnimation, value: isTargeted)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay(border)
                .animation(borderAnimation, value: isTargeted)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(Color.secondary.opacity(isTargeted ? 0.5 : 0.25),
                          lineWidth: isTargeted ? 1.5 : 1)
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
