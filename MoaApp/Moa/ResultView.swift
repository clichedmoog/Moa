import SwiftUI
import MoaKit

struct ResultView: View {
    let report: MoaReport
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let warning = report.volumeWarning {
                Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 실패는 아래 스크롤 목록에만 두지 않는다 — 목록이 길면 스크롤해서
            // 지나칠 수 있고, 그러면 9개를 바꾸고 1개를 실패해도 "성공"으로만
            // 읽힌다. 스크롤 밖에, 항상 보이는 자리에 따로 알린다.
            if !report.failed.isEmpty {
                Label("\(report.failed.count)개 항목을 처리하지 못했습니다",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("변환됨", entries: report.renamed, symbol: "checkmark.circle", tint: .green)
                    section("건너뜀", entries: report.skipped, symbol: "minus.circle", tint: .secondary)
                    section("실패", entries: report.failed, symbol: "xmark.circle", tint: .red, highlighted: true)
                }
            }
            .frame(maxHeight: 220)

            HStack {
                Spacer()
                Button("확인", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.hasChanges ? "\(report.renamed.count)개의 이름을 고쳤습니다"
                                   : "고칠 이름이 없었습니다")
                .font(.title3.bold())

            if report.alreadyNormalized > 0 {
                Text("이미 정상인 항목 \(report.alreadyNormalized)개는 건드리지 않았습니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, entries: [ReportEntry],
                         symbol: String, tint: Color, highlighted: Bool = false) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(title) \(entries.count)", systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)

                ForEach(Array(entries.prefix(50).enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 1) {
                        Text((entry.path as NSString).lastPathComponent)
                            .font(.callout)
                        // 실패 사유는 그대로 보여준다. NormalizationService 가
                        // 흔한 errno 는 한글로 옮기고 나머지는 "실패 (errno N)"
                        // 로 떨어뜨리는데, 그 fallback 문구까지 자르거나
                        // 다듬지 않는다 — 지금은 이게 원인을 알 유일한 방법이다.
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 22)
                }

                if entries.count > 50 {
                    Text("외 \(entries.count - 50)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 22)
                }
            }
            .padding(highlighted ? 8 : 0)
            .background(highlighted ? Color.red.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
