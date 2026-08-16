import SwiftUI
import MoaKit

/// 변환 대상이 임계값을 넘었을 때만 나타난다.
/// 상위 폴더를 잘못 드롭하는 사고를 막는 유일한 장치다.
struct ConfirmView: View {
    let preview: NormalizationPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("\(preview.targetCount)개를 모읍니다")
                .font(.title2.bold())

            Text("전체 \(preview.totalCount)개 항목을 확인했습니다.\n의도한 폴더가 맞는지 확인해 주세요.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let warning = preview.volumeWarning {
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button("취소", action: onCancel)
                Button("모으기", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 320)
    }
}
