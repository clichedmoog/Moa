import SwiftUI
import MoaKit

struct ResultView: View {
    let report: MoaReport
    /// 이 결과를 보는 동안 Dock 등으로 더 들어와 뒤에서 기다리고 있는 항목 수.
    /// 0이면 평소처럼 "확인"만 보여준다.
    let pendingCount: Int
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
                if pendingCount > 0 {
                    Text("대기 중인 항목 \(pendingCount)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(pendingCount > 0 ? "확인하고 다음 처리" : "확인", action: onDone)
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
    /// `failed` 가 아니라 `hasUnfixed` 를 본다. 이름 충돌로 건너뛴 항목은
    /// `failed` 에 없지만 고쳐야 할 파일이 그대로 남은 것이라, 체크 표시를 띄우면
    /// F1 과 같은 거짓 성공이 된다.
    private var outcome: DoneMark.Outcome {
        if report.hasUnfixed { return .hadFailures }
        return report.hasChanges ? .changed : .nothingToDo
    }

    // `outcome` 과 같은 3단 우선순위를 따른다 — 실패가 있으면 "이미 모두
    // 모아져 있습니다"라고 말하면 안 된다. 그건 아무 문제도 없었다는 뜻인데,
    // 바로 아래 빨간 배너가 실패를 알리는 중이라면 거짓이다.
    // 일부라도 모았다면 그 개수는 여전히 사실이므로 그대로 둔다 — 실패는
    // 빨간 배너가 전달한다.
    private var headline: String {
        switch outcome {
        case .hadFailures:
            return report.hasChanges ? "\(report.renamed.count)개를 모았습니다"
                                     : "모으지 못했습니다"
        case .changed:
            return "\(report.renamed.count)개를 모았습니다"
        case .nothingToDo:
            return "이미 모두 모아져 있습니다"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            DoneMark(outcome: outcome)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
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
