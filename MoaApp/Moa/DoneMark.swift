import SwiftUI

/// 결과 화면의 완료 표시. 원이 한 바퀴 그려지고, 이어서 획이 그어진다.
///
/// 자모 마크(`GatherMark`)를 여기 두지 않는 이유는, 그 마크가 하는 말이
/// "흩어진 것이 모인다"이고 그건 **일이 벌어지는 동안** 할 말이기 때문이다.
/// 결과 화면에서 필요한 건 끝났다는 신호뿐이고, 무슨 일이 있었는지는 글이 말한다.
struct DoneMark: View {

    enum Outcome {
        /// 무언가 고쳤다.
        case changed
        /// 고칠 게 없었다. **이것도 좋은 결과다** — 사용자가 부탁한 일은 끝났고
        /// 파일은 이미 온전했다. 회색으로 눅이면 실패처럼 읽히므로 초록을 함께 쓴다.
        case nothingToDo
        /// 일부가 실패했다. 체크를 띄우면 거짓말이 된다.
        case hadFailures
    }

    var outcome: Outcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ringProgress: CGFloat = 0
    @State private var strokeProgress: CGFloat = 0
    @State private var settle: CGFloat = 0.86

    private var tint: Color {
        outcome == .hadFailures ? .orange : .green
    }

    var body: some View {
        ZStack {
            // 옅게 깔린 채움 — 원이 닫힌 뒤 배어 나온다.
            Circle()
                .fill(tint.opacity(0.12 * ringProgress))

            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            mark
                .trim(from: 0, to: strokeProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                .frame(width: 26, height: 26)
        }
        .frame(width: 48, height: 48)
        .scaleEffect(settle)
        .onAppear(perform: play)
        .accessibilityHidden(true)
    }

    /// 체크와 느낌표를 같은 방식(획을 긋는 것)으로 그린다. SF Symbol 을 키우면
    /// 획이 그어지는 게 아니라 도장처럼 찍혀서, 원이 그려지는 동작과 어긋난다.
    private var mark: Path {
        Path { p in
            switch outcome {
            case .changed, .nothingToDo:
                p.move(to: CGPoint(x: 3, y: 14))
                p.addLine(to: CGPoint(x: 10, y: 20))
                p.addLine(to: CGPoint(x: 23, y: 6))
            case .hadFailures:
                p.move(to: CGPoint(x: 13, y: 5))
                p.addLine(to: CGPoint(x: 13, y: 16))
                p.move(to: CGPoint(x: 13, y: 21))
                p.addLine(to: CGPoint(x: 13, y: 21.6))
            }
        }
    }

    private func play() {
        guard !reduceMotion else {
            ringProgress = 1; strokeProgress = 1; settle = 1
            return
        }
        // 원이 먼저 한 바퀴, 그 끝에서 획이 이어받고, 마지막에 살짝 자리를 잡는다.
        withAnimation(.easeInOut(duration: 0.38)) { ringProgress = 1 }
        withAnimation(.easeOut(duration: 0.26).delay(0.30)) { strokeProgress = 1 }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.58).delay(0.26)) { settle = 1 }
    }
}
