import SwiftUI

/// 앱의 서명. "모아"(모으다)라는 이름 그 자체를 상태로 보여준다 — 대기 중엔
/// 자모가 흩어져 있다가, 무슨 일이든 시작되는 순간 각자 속한 음절 안에서
/// 앉을 자리를 향해 모여들고, 도착하는 순간 실제 낱말 "모아"에 자리를
/// 넘긴다. 이 앱이 하는 일을 한 요소로 압축한 것이라 다른 어떤 화면에도,
/// 다른 어떤 앱에도 재사용하지 않는다.
///
/// 도착 지점(`arrival` 벡터·`componentScale`)은 이론이 아니라 스크린샷을
/// 겹쳐 보며 맞춘 값이다 — `ㅁ`은 "모" 블록 위쪽, `ㅗ`는 그 아래, `ㅇ`은
/// "아" 블록 왼쪽, `ㅏ`는 오른쪽. 정확히 자리를 잡으면 완성된 낱말로
/// 넘어가는 순간이 저절로 사라진다.
struct GatherMark: View {
    enum Phase: Equatable {
        /// 대기 — 자모가 흩어져 있다.
        case scattered
        /// 그 밖의 모든 상태(드래그 진입/작업 중/완료) — 이미 "모아"로 모여 있다.
        case leaning
        case gathering
        case settled
        /// TEMP: 도착 지점 정렬 확인용. 커밋 전 제거.
        case debugArrived
    }

    var phase: Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size: CGFloat = 36
    private static let travel: CGFloat = 26
    private static let componentScale: CGFloat = 0.56

    private static let mieumVector = CGSize(width: -0.55, height: -1.05)
    private static let oVector = CGSize(width: -0.55, height: 1.05)
    private static let ieungVector = CGSize(width: 0.5, height: 0)
    private static let aVector = CGSize(width: 1.15, height: 0)

    // 스크린샷으로 맞춘 도착 지점 — 아래 "실측 로그" 참고.
    private static let mieumArrival = CGSize(width: -18, height: -9)
    private static let oArrival = CGSize(width: -18, height: 9)
    private static let ieungArrival = CGSize(width: 15, height: 0)
    private static let aArrival = CGSize(width: 24, height: 0)

    private var isGathered: Bool { phase != .scattered && phase != .debugArrived }
    private var isArrived: Bool { phase != .scattered }

    private var jamoAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    private var wordAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82).delay(0.08)
    }

    var body: some View {
        ZStack {
            jamo("ㅁ", Self.mieumVector, Self.mieumArrival)
            jamo("ㅗ", Self.oVector, Self.oArrival)
            jamo("ㅇ", Self.ieungVector, Self.ieungArrival)
            jamo("ㅏ", Self.aVector, Self.aArrival)

            Text("모아")
                .font(.system(size: Self.size, weight: .heavy))
                .tracking(-1.5)
                .foregroundStyle(.primary)
                .opacity(isGathered ? 1 : 0)
                .scaleEffect(isGathered ? 1 : 0.9)
                .animation(wordAnimation, value: isGathered)
        }
        .frame(height: Self.size + 30)
        .accessibilityHidden(true)
    }

    private func jamo(_ letter: String, _ scatterVector: CGSize, _ arrival: CGSize) -> some View {
        Text(letter)
            .font(.system(size: Self.size, weight: .heavy))
            .foregroundStyle(.secondary)
            .opacity(phase == .debugArrived ? 1 : (isGathered ? 0 : 0.4))
            .scaleEffect(isArrived ? Self.componentScale : 1)
            .offset(x: isArrived ? arrival.width : scatterVector.width * Self.travel,
                    y: isArrived ? arrival.height : scatterVector.height * Self.travel)
            .animation(jamoAnimation, value: isArrived)
    }
}
