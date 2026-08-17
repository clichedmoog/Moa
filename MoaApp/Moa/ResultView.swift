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
            // 지나칠 수 있고, 그러면 9개를 모으고 1개를 실패해도 "성공"으로만
            // 읽힌다. 스크롤 밖에, 항상 보이는 자리에서 무뎌지지 않은 문장으로 알린다.
            if !report.failed.isEmpty {
                Label("\(report.failed.count)개는 고치지 못했습니다",
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
                    section("건너뜀", entries: report.skipped, symbol: "minus.circle", tint: .orange)
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

    // 자모 마크 대신 완료 표시를 둔다. 그 마크가 하는 말은 "흩어진 것이 모인다"이고
    // 그건 일이 벌어지는 동안 할 말이다. 여기서 필요한 건 끝났다는 신호뿐이고,
    // 무슨 일이 있었는지는 아래 글이 말한다.
    private var outcome: DoneMark.Outcome {
        if !report.failed.isEmpty { return .hadFailures }
        return report.hasChanges ? .changed : .nothingToDo
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            DoneMark(outcome: outcome)

            VStack(alignment: .leading, spacing: 4) {
                Text(report.hasChanges ? "\(report.renamed.count)개를 모았습니다"
                                       : "이미 모두 모아져 있습니다")
                    .font(.title2.bold())

                if report.alreadyNormalized > 0 {
                    Text("이미 정상인 항목 \(report.alreadyNormalized)개는 건드리지 않았습니다")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
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
                        // 실패 사유는 그대로 보여준다. errno fallback 문구까지
                        // 자르거나 다듬지 않는다.
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
