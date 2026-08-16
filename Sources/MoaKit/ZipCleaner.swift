import Foundation
import ZIPFoundation

public enum ZipCleanerError: Error, Equatable {
    case unreadableArchive
    case entryExtractionFailed(String)
}

/// 기존 ZIP 의 엔트리명을 NFC 로 고치고 맥 전용 파일을 제거해 다시 쓴다.
///
/// 엔트리를 디스크에 풀지 않고 메모리로 옮기므로 `../` 를 이용한 경로 탈출(Zip Slip)이
/// 원천적으로 불가능하다. 원본 아카이브는 수정하지 않는다.
public enum ZipCleaner {

    /// 윈도우 한국어판이 쓰는 CP949(EUC-KR 확장).
    private static let cp949 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))

    public static func defaultDestination(for source: URL) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        return source.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-정리됨.zip")
    }

    /// `destination` 이 `source` 와 같은 파일이어도 안전하다.
    ///
    /// 저장 패널이 제안한 `-정리됨` 을 지우고 원래 이름으로 저장하는 건 자연스러운 행동이다.
    /// 목적지에 직접 쓰면 읽는 중인 아카이브가 깨지므로, 임시 파일에 다 만든 뒤
    /// 마지막에 한 번 옮긴다. 읽기는 그 전에 모두 끝나 있다.
    public static func clean(archiveAt source: URL, to destination: URL) throws -> ZipResult {
        // `pathEncoding: nil` 을 명시해야 한다. 라벨 없이 `Archive(url:accessMode:)` 만
        // 쓰면 이 throwing 이니셜라이저와 deprecated 된 failable
        // `init?(url:accessMode:preferredEncoding:)` 가 둘 다 `try?` 문맥에 맞아떨어져
        // 컴파일러가 후자를 고른다 — 그러면 `try?` 는 아무것도 던지지 않는 호출을
        // 감싸는 장식이 되고 진짜 에러 정보가 사라진다(실측: "no calls to throwing
        // functions occur within 'try' expression" 경고).
        guard let input = try? Archive(url: source, accessMode: .read, pathEncoding: nil) else {
            throw ZipCleanerError.unreadableArchive
        }
        let temporary = ArchivePlacement.makeTemporaryURL()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try Archive(url: temporary, accessMode: .create)

        var entryCount = 0
        var omitted: [ReportEntry] = []

        for entry in input {
            let rawName = rawBytes(of: entry)
            let display = normalizedName(from: rawName, fallback: entry.path)
            let components = rawName.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: true)
            if components.contains(where: { ZipExclusions.shouldExclude(name: Array($0)) }) {
                omitted.append(ReportEntry(path: display, detail: "맥 전용 파일"))
                continue
            }
            // 여기서 ZipExclusions 는 ZipWriter 에서와 달리 **실제로 일한다.**
            // ZipWriter 경로에서는 TreeWalker 가 점으로 시작하는 이름을 먼저 걸러
            // 대부분의 패턴이 도달하지 못하지만, 여기서는 아카이브 엔트리 이름을
            // 날것으로 읽으므로 모든 패턴이 유효하다.
            guard entry.type == .file else {
                // 디렉터리 엔트리는 파일 경로에 이미 포함되므로 누락이 아니다.
                if entry.type == .symlink {
                    omitted.append(ReportEntry(path: display, detail: "심볼릭 링크 — 아카이브에 넣지 않음"))
                }
                continue
            }

            var payload = Data()
            do {
                _ = try input.extract(entry, bufferSize: 64 * 1024, skipCRC32: true) {
                    payload.append($0)
                }
            } catch {
                throw ZipCleanerError.entryExtractionFailed(entry.path)
            }

            let name = normalizedName(from: rawName, fallback: entry.path)
            let data = payload
            try output.addEntry(with: name, type: .file,
                                uncompressedSize: Int64(data.count),
                                compressionMethod: .deflate) { position, size in
                let start = Int(position)
                return data.subdata(in: start..<min(start + size, data.count))
            }
            entryCount += 1
        }

        try ArchivePlacement.place(temporary: temporary, at: destination)
        // `failed` 는 여기서는 항상 빈 배열이다 — `ZipWriter` 와 같은 타입을 쓰지만
        // 의미가 다르다. `ZipWriter` 는 파일시스템을 순회하며 부분 성공을 허용한다
        // (권한 없는 폴더 하나 때문에 나머지까지 포기하지 않는다). `ZipCleaner` 는
        // 반대로 엔트리 하나를 못 읽으면 `entryExtractionFailed` 로 즉시 throw 해
        // 전체를 중단한다 — 손상된 원본 zip 에서 일부만 담긴 결과물을 조용히
        // 내놓는 것이 절반의 성공을 기록하는 것보다 나쁘다고 판단해서다. 그러니
        // `failed` 가 비어 있다고 해서 "실패한 항목이 없었다"로 읽으면 안 된다 —
        // 이 타입에서는 애초에 채워질 수가 없다.
        return ZipResult(entryCount: entryCount, omitted: omitted, failed: [])
    }

    /// 엔트리명의 원시 바이트를 복원한다.
    ///
    /// ZIPFoundation 은 UTF-8 플래그를 공개하지 않는다. `isoLatin1` 은 0x00~0xFF 를
    /// U+0000~U+00FF 로 1:1 대응시키므로 이 왕복이 원시 바이트를 무손실로 되살린다.
    private static func rawBytes(of entry: Entry) -> [UInt8] {
        guard let data = entry.path(using: .isoLatin1).data(using: .isoLatin1) else {
            return Array(entry.path.utf8)
        }
        return Array(data)
    }

    /// UTF-8 → CP949 → 포기 순으로 판정한다. 추측으로 이름을 망가뜨리지 않는다.
    ///
    /// 실제 NFC 변환은 `Normalizer.normalized(_:)` 하나에만 맡긴다 — 이 함수가
    /// `precomposedStringWithCanonicalMapping` 을 직접 부르는 사본을 또 갖고 있으면
    /// 두 규칙이 시간이 지나며 서로 다르게 벌어질 수 있다.
    private static func normalizedName(from raw: [UInt8], fallback: String) -> String {
        if String(bytes: raw, encoding: .utf8) != nil {
            return String(decoding: Normalizer.normalized(raw), as: UTF8.self)
        }
        if let text = String(bytes: raw, encoding: cp949) {
            return String(decoding: Normalizer.normalized(Array(text.utf8)), as: UTF8.self)
        }
        // 여기까지 왔다는 건 raw 가 UTF-8 로도 CP949 로도 디코드되지 않았다는 뜻이다.
        // `fallback`(ZIPFoundation 이 스스로 디코드한 entry.path)도 빈 문자열일 수
        // 있다 — 엔트리가 UTF-8 플래그를 세웠는데 정작 원시 바이트는 유효한 UTF-8
        // 이 아닌, 모순된(그러나 파싱은 되는) zip 이 그 경우다. 이때 `String
        // (pathData:encoding:)` 은 내부적으로 `?? ""` 로 떨어진다. 빈 이름으로
        // 엔트리를 새 아카이브에 넣을 수는 없으므로(이름이 없는 파일이 되어버린다),
        // 그 경우에만 원시 바이트에서 결정적으로 이름을 합성한다. 원시 바이트가
        // 같으면 항상 같은 이름이 나오므로 재실행해도 결과가 흔들리지 않는다.
        guard !fallback.isEmpty else {
            return "이름없음-\(raw.map { String(format: "%02x", $0) }.joined())"
        }
        return fallback
    }
}
