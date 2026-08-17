import SwiftUI

/// 앱의 서명. "모아"(모으다)라는 이름 그 자체를 상태로 보여준다 — 대기 중엔
/// 자모가 멀리 흩어져 흐릿하게 떠 있다가, 무슨 일이든 시작되는 순간 서로를
/// 향해 모여들며 또렷해진다. 이 앱이 하는 일을 한 요소로 압축한 것이라
/// 다른 어떤 화면에도, 다른 어떤 앱에도 재사용하지 않는다.
///
/// **끝까지 낱자모로 남는다.** 완성된 "모아" 글자로 넘기지 않는다.
/// 격리된 낱자모 글리프는 완성 음절 안의 구성 요소와 외곽선도 크기도 달라서
/// 아무리 맞춰도 넘어가는 순간이 티가 난다. 합쳐지는 *척*을 하지 않으면
/// 맞출 대상 자체가 없어지고, 남는 건 "흩어진 것이 모인다"는 사실뿐이다 —
/// 그게 이 앱이 하는 일이기도 하다.
///
/// 위치는 이론으로 유도하지 않는다. **화면을 보며 맞춘 값만 신뢰한다** —
/// 아래 `Tuning` 이 그 값들이고, 여기 말고 다른 곳에 위치 상수를 두지 않는다.
struct GatherMark: View {

    // MARK: - 조정값
    //
    // 기준점은 마크의 중앙. x 는 오른쪽이 +, y 는 아래쪽이 +, 단위는 포인트.
    // 글자 크기가 36pt 이므로 한 글자 폭은 대략 30pt 다.
    //
    //            흩어졌을 때        모였을 때        모였을 때 크기
    //   ㅁ       위왼쪽            "모" 위쪽         componentScale
    //   ㅗ       아래왼쪽          "모" 아래쪽       componentScale
    //   ㅇ       오른쪽 안         "아" 왼쪽         componentScale
    //   ㅏ       오른쪽 바깥       "아" 오른쪽       componentScale

    private enum Tuning {
        /// 낱자모 글자 크기.
        static let fontSize: CGFloat = 36
        /// 모였을 때의 크기 배율.
        /// **1.0 — 글자 크기는 처음부터 끝까지 변하지 않는다.** 움직이는 것은
        /// 위치와 진하기뿐이다. 크기까지 변하면 "모인다"가 아니라 "멀어진다"로
        /// 읽혀서, 정작 하려던 말과 어긋난다.
        static let gatheredScale: CGFloat = 1.0

        /// 흩어졌을 때 / 모였을 때의 진하기.
        static let scatteredOpacity: CGFloat = 0.4
        static let gatheredOpacity: CGFloat = 1.0

        /// 마크가 차지하는 자리. 흩어진 상태의 바깥 끝(±55, ±30)에
        /// 글자 반 폭을 더한 값이다. 여기를 줄이면 이웃 뷰가 자모를 덮는다.
        static let markWidth: CGFloat = 150
        static let markHeight: CGFloat = 96

        /// 자모마다 다른 단청 안료를 준다. **모였을 때만** 이 색이 오고,
        /// 흩어져 있을 땐 무채색이다 — 색이 오는 것 자체가 "모였다"는 신호가 된다.
        ///
        /// 대기 상태가 조용해야 변화가 눈에 들어온다. 색을 늘 켜두면 모이는 순간에
        /// 달라지는 게 진하기뿐이라 사건이 밋밋해진다. 앱의 정체성은 Dock 의 아이콘이
        /// 계속 보여주므로, 창 안에서까지 색을 붙들고 있을 이유가 없다.
        ///
        /// 단청은 원래 여러 광물 안료를 배열하는 것이라, 넷을 같은 색으로 두는 편이
        /// 오히려 출처에서 멀다. 다만 **광물 안료의 탁한 톤을 지킨다** — 디지털 원색으로
        /// 올리면 결과 화면이 의미로 쓰는 빨강·주황·초록과 섞여, 사용자가 장식과 신호를
        /// 구분하지 못한다. 실제 석간주는 소방차 빨강이 아니라 흙빛이고 자황도 레몬이
        /// 아니라 황토다. 그 탁함이 이 색들을 "전통 팔레트"로 읽히게 하고 "상태 표시"로는
        /// 읽히지 않게 한다.
        ///
        /// 배치도 임의가 아니다 — "모"(ㅁㅗ)는 찬 계열, "아"(ㅇㅏ)는 더운 계열로 묶어
        /// 왼쪽이 차고 오른쪽이 따뜻하다. 넷이 흩어져도 두 덩이로 읽힌다.
        static let ink: [Character: Color] = [
            "ㅁ": pigment("samcheong",  light: (0.16, 0.33, 0.52), dark: (0.42, 0.60, 0.80)),
            "ㅗ": pigment("noerok",     light: (0.22, 0.40, 0.36), dark: (0.44, 0.66, 0.60)),
            "ㅇ": pigment("jahwang",    light: (0.62, 0.46, 0.14), dark: (0.85, 0.70, 0.36)),
            "ㅏ": pigment("seokganju",  light: (0.56, 0.26, 0.19), dark: (0.78, 0.45, 0.37)),
        ]

        private static func pigment(_ name: String,
                                    light: (CGFloat, CGFloat, CGFloat),
                                    dark: (CGFloat, CGFloat, CGFloat)) -> Color {
            Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
                let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            })
        }

        static let scattered: [Character: CGSize] = [
            "ㅁ": CGSize(width: -30, height: -30),
            "ㅗ": CGSize(width: -34, height:   8),
            "ㅇ": CGSize(width:  14, height: -26),
            "ㅏ": CGSize(width:  55, height: -26),
        ]

        // 크기를 줄이지 않게 되면서, 0.62 배 기준으로 맞췄던 값을
        // 같은 배치가 유지되도록 1/0.62 배 넓혔다.
        static let gathered: [Character: CGSize] = [
            "ㅁ": CGSize(width: -26, height: -16),
            "ㅗ": CGSize(width: -26, height:   3),
            "ㅇ": CGSize(width:  13, height:  -6),
            "ㅏ": CGSize(width:  34, height:  -6),
        ]
    }

    // MARK: -

    enum Phase: Equatable {
        /// 대기 — 자모가 흩어져 있다.
        case scattered
        /// 드래그가 들어옴 — 모이기 시작한다.
        case leaning
        /// 작업 중.
        case gathering
        /// 완료 — 낱말로 정착했다.
        case settled
    }

    var phase: Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let order: [Character] = ["ㅁ", "ㅗ", "ㅇ", "ㅏ"]

    private var isGathered: Bool { phase != .scattered }

    // 자모가 먼저 움직이고 낱말이 살짝 늦게 뒤따른다. 겹치는 구간에서 자모는
    // 이미 옅어지는 중이라 둘 다 또렷한 프레임이 생기지 않는다.
    private var jamoAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.29)
    }


    var body: some View {
        ZStack {
            ForEach(Self.order, id: \.self) { letter in
                jamo(letter)
            }
        }
        // `offset` 은 레이아웃 크기를 바꾸지 않는다 — 자모가 아무리 멀리 흩어져도
        // SwiftUI 는 이 뷰를 글자 한 자 크기로 보고 이웃을 바짝 붙인다. 그래서
        // 흩어진 상태가 실제로 차지하는 만큼을 폭으로도 직접 잡아준다.
        .frame(width: Tuning.markWidth, height: Tuning.markHeight)
        // 각 화면의 문구가 이미 상태를 말로 전달한다 — 이 요소는 장식이 아니라
        // 시각적 서명이라 VoiceOver 에 중복으로 읽히지 않게 숨긴다.
        .accessibilityHidden(true)
    }

    private func jamo(_ letter: Character) -> some View {
        let target = (isGathered ? Tuning.gathered : Tuning.scattered)[letter] ?? .zero
        // 무채색 겹과 안료 겹을 포개고 서로 반대로 흐리게 해서 색을 건넨다.
        // `foregroundStyle` 에 명암 대응 색을 직접 넣으면 SwiftUI 가 두 색 사이를
        // 보간하지 못해 색만 툭 바뀐다 — 위치는 미끄러지는데 색은 끊기면 그게 더 눈에 띈다.
        return ZStack {
            glyph(letter)
                .foregroundStyle(.secondary)
                .opacity(isGathered ? 0 : 1)
            glyph(letter)
                .foregroundStyle(Tuning.ink[letter] ?? .primary)
                .opacity(isGathered ? 1 : 0)
        }
        .opacity(isGathered ? Tuning.gatheredOpacity : Tuning.scatteredOpacity)
        .scaleEffect(isGathered ? Tuning.gatheredScale : 1)
        .offset(x: target.width, y: target.height)
        .animation(jamoAnimation, value: isGathered)
    }

    private func glyph(_ letter: Character) -> some View {
        Text(String(letter))
            .font(.system(size: Tuning.fontSize, weight: .heavy))
    }
}
