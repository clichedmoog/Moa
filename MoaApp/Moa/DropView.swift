import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DropView: View {
    @EnvironmentObject var coordinator: DropCoordinator
    @State private var isTargeted = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))

            VStack(spacing: 14) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

                Text("파일이나 폴더를 여기에 놓으세요")
                    .font(.headline)

                Text("자소분리된 이름을 모아쓰기로 고칩니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // 드롭이 어려운 사용자를 위한 대안. 선행 앱 Contact 의 UX 를 따른다.
                if isHovering {
                    Button("파일 선택…") { openPanel() }
                        .buttonStyle(.borderedProminent)
                }
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
