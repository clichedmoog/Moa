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
        guard let input = try? Archive(url: source, accessMode: .read) else {
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
        // 아카이브 엔트리를 읽는 작업이라 파일시스템 순회 실패라는 개념이 없다.
        // 엔트리를 못 읽으면 위에서 throw 한다.
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
    private static func normalizedName(from raw: [UInt8], fallback: String) -> String {
        if let text = String(bytes: raw, encoding: .utf8) {
            return text.precomposedStringWithCanonicalMapping
        }
        if let text = String(bytes: raw, encoding: cp949) {
            return text.precomposedStringWithCanonicalMapping
        }
        return fallback
    }
}
