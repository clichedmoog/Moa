# 모아 (Moa) — 설계

작성일: 2026-08-16
대상 버전: 1.0

## 1. 개요

macOS에서 자소분리(유니코드 NFD)된 한글 파일명을 NFC로 정규화하는 macOS 앱.
드래그앤드롭으로 동작하며, 파일명 변환과 "윈도우에서 깨지지 않는 ZIP" 생성을 함께 제공한다.

## 2. 확정된 결정

| 항목 | 결정 |
| --- | --- |
| 앱 형태 | 드래그앤드롭 창 하나 (Finder 확장은 1.1 이후) |
| 안전장치 | 즉시 변환. 단 대상 500개 초과 시 1회 확인 |
| 압축 기능 | 새 ZIP 생성 + 기존 ZIP 정리 둘 다 |
| Dock 드롭 | 지원 |
| 배포 | GitHub Release(Developer ID + 공증) + Mac App Store 병행 |
| 구조 | 코어를 `MoaKit` Swift Package로 분리 |
| 아키텍처 | Universal (arm64 + x86_64) |
| 최소 지원 | macOS 13 Ventura |
| 번들 ID | `com.clichedmoog.Moa` (App Store 등록 시 팀 ID에 맞춰 변경 가능) |

## 3. 실측 결과 — 설계의 근거

2026-08-15 실측. 모든 수치는 `readdir(3)`로 읽은 디스크 원시 바이트 기준이다.
아래 결과가 코어 설계를 직접 결정하므로 구현 전 반드시 읽는다.

### 3.1 Foundation 경로 API는 사용할 수 없다

가장 중요한 발견이다. `FileManager.moveItem`은 **성공(에러 없음)을 반환하면서 파일명을 전혀 바꾸지 않는다.**

| API | NFD → NFC rename 결과 |
| --- | --- |
| `FileManager.moveItem(atPath:toPath:)` | ❌ 조용히 실패. 디스크는 NFD 유지 |
| `URL(fileURLWithPath:)` 경유 | ❌ 동일 |
| POSIX `rename(2)` + Swift String | ✅ 성공. 디스크가 NFC로 변경됨 |
| POSIX `rename(2)` + 명시적 UTF-8 바이트 | ✅ 성공 |

원인은 `NSString.fileSystemRepresentation`이 경로를 커널에 넘기기 전에 NFD로 변환하기 때문이다.
NFC 문자열 `한.txt`(`U+D55C`)를 넘겨도 실제 syscall에 도달하는 바이트는 `E1 84 92 E1 85 A1 E1 86 AB`(NFD)다.
결국 "NFD → NFD" rename이 되어 아무 일도 일어나지 않는다.

> **이것이 이 프로젝트에서 가장 위험한 실패 양식이다.** 에러가 없으므로 테스트 없이 구현하면
> "정상 동작한다"고 믿은 채 릴리스하게 된다. 코어는 반드시 디스크 바이트를 직접 검증한다.

읽기 방향은 안전하다. `readdir`, `contentsOfDirectory`, `URL.lastPathComponent` 모두
디스크 원시 바이트를 그대로 돌려준다(세 파일시스템에서 일치 확인).

### 3.2 APFS는 임시 이름 경유가 불필요하다

HANDOFF에서 실측 대상으로 지목한 항목이다. 결론은 **불필요**.
APFS는 normalization-preserving이며, `rename(2)` 한 번으로 NFD → NFC가 반영된다.

`O_CREAT|O_EXCL`로 검증한 결과 APFS·exFAT·HFS+ 모두 **normalization-insensitive**다.
정규화 형태만 다른 두 이름은 같은 파일로 취급되어 공존할 수 없다.
따라서 순수 정규화 rename에서 **다른 파일과의 이름 충돌은 원칙적으로 발생하지 않는다.**
(대소문자 구분 APFS, SMB/NFS 등 미검증 볼륨을 위해 방어 로직은 유지한다. 4.2 참조.)

### 3.3 파일시스템별 거동 — HANDOFF 표를 정정한다

NFC 바이트로 직접 생성한 뒤 디스크에 남은 바이트:

| 파일시스템 | 결과 | HANDOFF 서술 |
| --- | --- | --- |
| APFS | ✅ NFC 보존 | 일치 |
| HFS+ | ❌ NFD 강제 | 일치 |
| exFAT | ❌ **NFD 강제** | ❌ "저장한 그대로 보존" — **틀림** |

exFAT은 rename뿐 아니라 **NFC 이름으로 새로 만들어도** macOS 드라이버가 NFD로 되돌린다.

> **따라서 exFAT USB에 담긴 파일명은 맥에서 고칠 수 없다.**
> 모아의 실효 범위는 APFS 볼륨 위에서 이름을 고쳐두고 그 상태로 압축·전송하는 시나리오다.
> USB 시나리오의 해법은 파일명 변환이 아니라 **ZIP 생성**이다(4.5).

### 3.4 macOS 기본 압축은 UTF-8 플래그를 세우지 않는다

APFS에서 NFC로 고친 파일을 압축한 결과:

| 도구 | 엔트리명 바이트 | UTF-8 플래그(bit 11) |
| --- | --- | --- |
| `ditto -c -k` | NFC | ❌ False |
| `zip -r` | NFC | ❌ False |
| ZIPFoundation | NFC | ✅ True |

플래그가 꺼져 있으면 윈도우 탐색기는 엔트리명을 CP949로 해석한다.
이름을 NFC로 완벽히 고쳐도 맥 기본 압축으로 묶으면 윈도우에서 여전히 깨진다.
사용자가 겪는 "맥에서 압축한 zip이 윈도우에서 깨짐"은 자소분리와 이 플래그 문제가 겹친 결과다.

ZIPFoundation은 요건을 만족한다(UTF-8 플래그 자동, NFC 보존, MIT).
단 **기본 압축 방식이 `.none`(stored)이므로 `.deflate`를 명시해야 한다.**

## 4. 아키텍처

```
Moa/
├─ MoaKit/              Swift Package — UI 비의존, 전체 단위 테스트 대상
│   ├─ Normalizer       NFC 판단·변환
│   ├─ PathBytes        경로를 UTF-8 바이트로 다루는 타입
│   ├─ Renamer          POSIX rename(2) 래퍼
│   ├─ TreeWalker       bottom-up 순회
│   ├─ VolumeInspector  파일시스템 판별
│   ├─ ZipWriter        새 ZIP 생성
│   ├─ ZipCleaner       기존 ZIP 정리
│   └─ MoaReport        처리 결과 집계
├─ MoaApp/              SwiftUI 앱 타깃
└─ MoaKitTests/         NFD 픽스처를 코드로 생성해 검증
```

`MoaKit`은 AppKit·SwiftUI에 의존하지 않는다. GUI 없이 코어 전체를 검증하기 위해서다.
3.1의 조용한 실패를 잡으려면 이 분리가 필수다.

### 4.1 Normalizer

판단과 변환을 분리한다.

```swift
func needsNormalization(_ name: String) -> Bool
func normalized(_ name: String) -> String   // precomposedStringWithCanonicalMapping
```

**판단은 반드시 유니코드 스칼라 배열로 비교한다.**

```swift
Array(name.unicodeScalars) != Array(name.precomposedStringWithCanonicalMapping.unicodeScalars)
```

Swift의 `String ==`는 정규화를 무시하므로 `name == name.precomposedStringWithCanonicalMapping`은
**항상 `true`**를 돌려준다. 이 함정에 걸리면 "바꿀 항목이 하나도 없다"는 결론이 나온다.

변환 범위는 한글만이 아니라 **전체 문자**에 적용한다. 일본어 탁점, 라틴 악센트도 같은 문제를 겪으며
canonical mapping이라 의미가 보존된다.

### 4.2 Renamer

POSIX `rename(2)`을 직접 호출한다. **Foundation 경로 API 사용 금지**(3.1).
경로는 문자열이 아니라 UTF-8 바이트 배열(`PathBytes`)로 다룬다.

충돌 방어는 `lstat` + inode 비교로 한다.

| `lstat(dest)` 결과 | 판단 | 동작 |
| --- | --- | --- |
| 없음(ENOENT) | 안전 | rename 수행 |
| 있음 + `(st_dev, st_ino)` 일치 | 같은 파일 | rename 수행 (normalization-insensitive 볼륨의 정상 경로) |
| 있음 + `(st_dev, st_ino)` 불일치 | 진짜 충돌 | **건너뛰고 보고. 덮어쓰지 않는다** |

> **설계 정정**: 초안에서는 `renamex_np(RENAME_EXCL)`을 우선 사용하기로 했으나,
> 실측에서 exFAT이 `ENOTSUP`(errno 45)을 반환했다. 이식성이 없어 분기 복잡도만 늘어난다.
> `lstat` + inode 비교는 모든 볼륨에서 동작하고 판단 근거도 명확하므로 이쪽을 단일 경로로 채택한다.

`lstat`과 `rename` 사이에 TOCTOU 경합이 있으나, 단일 사용자 데스크톱 유틸리티에서는 수용한다.
덮어쓰기를 하지 않으므로 최악의 결과는 "건너뜀"이다.

**rename 후 검증한다.** `readdir`로 이름을 다시 읽어 NFC인지 확인하고, 아니면 실패로 보고한다.
3.1의 조용한 실패와 3.3의 NFD 강제 볼륨이 여기서 걸린다.

### 4.3 TreeWalker

**bottom-up 순회.** 부모 이름을 먼저 바꾸면 수집해둔 자식 경로가 전부 무효가 된다.
자식을 모두 처리한 뒤 부모를 처리한다.

`readdir(3)`로 직접 순회한다. 디스크 원시 바이트를 확실히 얻기 위해서다.

제외 규칙:

| 대상 | 처리 | 이유 |
| --- | --- | --- |
| 심볼릭 링크 | 링크 자신의 이름만 변환, **따라가지 않음** | 링크 하나로 엉뚱한 트리 전체가 대상이 된다 |
| 번들 패키지 | 이름만 변환, **내부 진입 안 함** | `.app`뿐 아니라 `.rtfd`·`.photoslibrary` 등 전체 |
| 숨김 항목 | 이름 변환·재귀 **모두 건너뜀** | `.git` 내부를 건드리면 저장소가 깨진다 |

번들 판정은 `UTType(filenameExtension:)?.conforms(to: .package)`로 한다.
`NSWorkspace.isFilePackage`는 AppKit 의존이라 코어에서 쓰지 않는다.

### 4.4 VolumeInspector

`statfs`의 `f_fstypename`으로 판별한다.

| 값 | 판정 |
| --- | --- |
| `apfs` | 정상 동작 |
| `hfs`, `exfat`, `msdos`, `smbfs` 등 | NFD 강제 볼륨 |

NFD 강제 볼륨은 **사전 경고와 사후 검증을 모두** 한다.
사전에 "이 볼륨은 파일명을 NFD로 되돌립니다 — 압축해서 옮기세요"를 안내하고,
변환 후에도 4.2의 검증으로 실제 결과를 확인한다.
미검증 파일시스템이 있을 수 있으므로 목록만 믿지 않는다.

### 4.5 ZipWriter — 새 ZIP 생성

원본을 건드리지 않고 옆에 새 `.zip`을 만든다.
디스크 위 이름은 못 고쳐도 ZIP 안의 이름은 우리가 쓰는 값이므로 온전히 NFC로 나간다.
**이것이 exFAT USB 시나리오의 유일한 해법이다**(3.3).

- 엔트리명: NFC로 정규화
- UTF-8 플래그: ZIPFoundation이 자동 설정
- 압축 방식: **`.deflate` 명시**(기본값이 `.none`이므로)
- 제외: `.DS_Store`, `._*`(AppleDouble), `__MACOSX/`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`

의존성은 ZIPFoundation(MIT)을 **버전 고정**해 추가한다. `Archive` 이니셜라이저 시그니처가
0.9.x와 1.0에서 다르므로(옵셔널 반환 → throws) 버전을 명시하지 않으면 빌드가 깨진다.
실측은 0.9.x에서 했다.

### 4.6 ZipCleaner — 기존 ZIP 정리

엔트리를 **디스크에 풀지 않고** 메모리 스트림으로 읽어 바로 새 아카이브에 쓴다.
임시 폴더를 거치지 않으므로 `../`를 이용한 Zip Slip이 원천 차단된다.

- 출력: `원본이름-정리됨.zip` (원본 보존)
- 엔트리명 NFC 정규화 + 4.5의 제외 목록 적용
- 암호가 걸렸거나 손상된 아카이브: 손대지 않고 사유 표시

**CP949 엔트리 처리**: 윈도우에서 만든 ZIP은 엔트리명이 CP949일 수 있다.
UTF-8 플래그가 없는 엔트리는 CP949 디코드를 시도하고, 실패하면
해당 엔트리를 **원본 바이트 그대로 복사**한다. 추측으로 이름을 망가뜨리지 않는다.

### 4.7 MoaApp

입력 경로 3가지가 모두 `[URL]`로 수렴해 동일 파이프라인을 탄다.

1. 창 드래그앤드롭 (SwiftUI `dropDestination`)
2. Dock 아이콘 드롭 (`CFBundleDocumentTypes` + `application(_:open:)`)
3. hover 시 나타나는 파일 선택 버튼

2번은 `application(_:open:)`(`[URL]` 수신)을 쓴다. Contact가 쓴 `application(_:openFiles:)`는
`[String]`을 받는 구형 API다.

드롭된 것이 `.zip`이면 정리 모드(4.6), 아니면 이름 변환 모드로 분기한다.

**500개 임계값의 기준은 "실제 변환 대상 개수"다.** 순회로 수집한 전체 항목 수가 아니라
`needsNormalization`이 `true`인 항목만 센다. 이미 NFC인 파일 수천 개를 드롭해도 확인창이 뜨지 않는다.
상위 폴더 오드롭을 막기 위한 유일한 안전판이다.

## 5. 데이터 흐름

```
드롭 [URL]
  │
  ├─ .zip 인가? ──── 예 ──→ ZipCleaner ──→ 원본이름-정리됨.zip
  │
  └─ 아니오
       │
       ├─ VolumeInspector: NFD 강제 볼륨이면 사전 경고
       ├─ TreeWalker: bottom-up 수집 (심볼릭 링크/번들/숨김 제외)
       ├─ 500개 초과면 1회 확인
       │
       └─ 각 항목마다
            ├─ Normalizer.needsNormalization → false면 "이미 정상"
            ├─ Renamer: lstat 충돌 검사 → rename(2)
            └─ 검증: readdir로 재확인 → NFD면 실패 처리
                 │
                 └─→ MoaReport 집계 → 결과 표시
```

## 6. 오류 처리

결과는 4가지로 분류해 표시한다.

| 분류 | 내용 |
| --- | --- |
| 변환됨 | rename 성공 + 검증 통과 |
| 이미 정상 | 처음부터 NFC. rename하지 않음(수정 시각 보존) |
| 건너뜀 | 이름 충돌 / 번들 내부 / 심볼릭 링크 대상 / 숨김 항목 |
| 실패 | 권한 없음, 검증 실패(NFD 강제 볼륨), ZIP 손상·암호 |

원칙:

- **검증 없는 성공 보고를 만들지 않는다.** 이 앱의 가장 위험한 실패 양식이다(3.1).
- **덮어쓰지 않는다.** 충돌은 건너뛰고 보고한다.
- **크래시하지 않는다.** 접근 불가 디렉터리를 만나도 해당 항목만 실패 처리하고 순회를 계속한다.
- **셸을 거치지 않는다.** POSIX 호출만 사용하므로 파일명을 통한 명령 주입이 불가능하다.

## 7. 테스트 전략

`MoaKitTests`에서 **NFD 픽스처를 코드로 생성해** 검증한다.
저장소에 NFD 파일명을 커밋하면 git·압축·체크아웃 과정에서 정규화될 수 있으므로,
테스트 실행 시점에 원시 바이트로 만든다.

필수 케이스:

- `needsNormalization`이 NFD를 `true`, NFC를 `false`로 판단하는가 (4.1의 함정)
- rename 후 **`readdir` 원시 바이트**가 NFC인가 (3.1의 조용한 실패)
- bottom-up 순회에서 부모/자식 이름이 모두 바뀌는가
- 심볼릭 링크를 따라가지 않는가
- 번들 패키지 내부에 진입하지 않는가
- 숨김 항목을 건드리지 않는가
- 이미 NFC인 항목의 수정 시각이 보존되는가
- 충돌 시 덮어쓰지 않는가 (inode 다른 파일을 인위적으로 만들어 검증)
- ZIP 엔트리에 UTF-8 플래그가 서고 이름이 NFC이며 `.deflate`인가

검증은 반드시 `readdir` 원시 바이트로 한다. Swift `String ==` 비교는 무의미하다.

## 8. 배포

하나의 코드베이스, 두 개의 빌드. entitlements만 xcconfig로 분기한다.

| | GitHub Release | Mac App Store |
| --- | --- | --- |
| 서명 | Developer ID + 공증 + DMG | App Store 배포 인증서 |
| 샌드박스 | 켬 (제약이 없다면) | 필수 |
| entitlements | `files.user-selected.read-write` | 동일 |
| 아키텍처 | Universal (arm64 + x86_64) | Universal |

Universal로 가는 이유는 선행 앱 Contact의 실패를 되풀이하지 않기 위해서다(9절).

서명·공증 절차:

1. Developer ID Application 인증서 발급 (**현재 미발급 — 로컬에 유효 인증서 0개**)
2. Hardened Runtime 활성화 (공증 필수 조건)
3. `xcrun notarytool store-credentials "MOA_NOTARY"`
4. `xcrun notarytool submit Moa.zip --keychain-profile "MOA_NOTARY" --wait`
5. `xcrun stapler staple Moa.app` 후 DMG로 묶어 배포

자격 증명은 커밋하지 않는다. `.gitignore`에 `*.p12`, `*.provisionprofile`, `.env` 등록 완료.

## 9. 선행 앱 Contact — 조사 결과

소스: https://github.com/namhokim/cocoa_app (**MIT, Copyright (c) 2019 Namho Kim**)

### 9.1 HANDOFF 정정

| HANDOFF 서술 | 실제 |
| --- | --- |
| "Java 기반이라 로제타 필요" | ❌ **Swift + Cocoa 네이티브.** 로제타가 필요한 건 맞으나 이유가 다르다 — 배포 바이너리가 `Mach-O thin x86_64` **인텔 전용 빌드**이기 때문 |
| "코드 사이닝 없음" | ✅ 정확. `Signature=adhoc`, `TeamIdentifier=not set`, `spctl` rejected, 공증 티켓 없음 |
| "2020년 제작, v1.0" | ⚠️ **v2.1까지** 존재(2020-10-13). 최소 macOS 10.11 |

### 9.2 Contact가 실제로 하는 일

파일 이름을 직접 바꾸지 않는다. `mv "옛이름" "새이름"` 줄을 나열한 `.sh` 파일을 Documents에 만들고
`chmod +x` 후 `/bin/sh`로 실행한 뒤 삭제한다.

이는 3.1의 벽에 김남호 님도 부딪혔다는 증거다. Foundation으로는 NFC 이름을 쓸 수 없으니
raw 바이트를 그대로 넘겨주는 `mv`를 거쳐 우회한 것이다.
서로 다른 두 경로에서 같은 결론이 나왔으므로 이 제약은 확실하다.

부수 소득: Contact는 `app-sandbox=true` + `files.user-selected.read-write`만으로 실제 동작해왔다.
샌드박스에서 사용자 선택 항목의 이름 변경이 가능하다는 실사용 증거다(10절 참조).

### 9.3 가져올 것

- bottom-up 재귀 구조 (자식 먼저, 부모 나중) — 정확하다
- `CFBundleDocumentTypes: "*"` + `application(_:openFiles:)`로 Dock 드롭 지원 — 검증된 경로
- hover 시 파일 선택 버튼 노출 UX

### 9.4 피할 것

1. **셸 명령 주입 취약점** — 파일명에서 `"`만 이스케이프하고 `$`, `` ` ``, `\`는 놔둔다.
   큰따옴표 안에서도 `$(...)`와 백틱은 확장되므로 `보고서$(rm -rf ~).txt` 같은 이름이
   임의 명령을 실행시킨다. 우리는 셸을 거치지 않아 문제 자체가 없다.
   **App Store 심사에서도 `/bin/sh` 실행은 거절 사유가 되기 쉬워, 우리 방식이 배포 양쪽 모두에 유리하다.**
2. `mv -f` — 충돌 시 말없이 덮어써 파일이 사라진다
3. 이미 NFC인 항목도 전부 `mv` — 건너뛰기 없음, 수정 시각이 바뀐다
4. `try!` — 접근 권한 없는 디렉터리에서 크래시
5. 숨김 항목 검사가 재귀 뒤에 있어 숨김 폴더 내부는 그대로 처리됨
6. 번들 제외가 `.app`뿐 — `.rtfd`, `.photoslibrary` 등이 뚫림
7. 심볼릭 링크를 따라감

### 9.5 라이선스 판단

MIT이므로 차용·수정·상용 배포 모두 허용되며 조건은 저작권 고지와 라이선스 전문 포함뿐이다.

그러나 **코드를 차용하지 않는다.** 구조 자체가 우리가 쓰지 않을 방식(셸 스크립트 생성)이고
9.4의 결함을 상속할 이유가 없다. 특히 `ADragDropView.swift`는 Contact 저작물이 아니라
**제3자(Soulchild/fluffy, 2018) 코드인데 저장소에 해당 라이선스가 없다.**
재배포 근거가 불분명하므로 손대지 않고 SwiftUI `dropDestination`으로 직접 구현한다.

**README에 선행 앱으로 크레딧을 남긴다.**

## 10. 샌드박스 실측 결과 (2026-08-16 완료)

`com.apple.security.app-sandbox` + `files.user-selected.read-write` 만 가진 ad-hoc 서명
프로브 앱을 만들어 실제로 파일을 드롭해 확인했다.
`NSHomeDirectory()` 가 `/Users/tenma/Library/Containers/com.clichedmoog.SandboxProbe/Data`
로 나와 **샌드박스가 실제로 활성**된 상태에서 얻은 결과다.

| 질문 | 결과 |
| --- | --- |
| 10.1 단일 파일 드롭의 이름 변경 | ✅ **`renamed`** — 동작한다 |
| 10.2 드롭된 항목의 부모 디렉터리에 파일 생성 | ❌ **`EPERM`(errno 1)** — 거부된다 |

### 10.1 — 해소됨

`~/Downloads` 의 실제 NFD 파일 하나를 드롭했더니 `Renamer.normalizeName` 이 `.renamed` 를
반환했다. 샌드박스는 드롭된 항목에 대해 이름 변경에 필요한 만큼의 권한을 부여한다.

**따라서 Mac App Store 배포에 기능적 장애가 없다.** 이는 선행 앱 Contact 가 같은 entitlement
조합으로 동작해온 정황(9.2)과도 일치한다.

### 10.2 — 확인됨. 설계를 바꾼다

부모 디렉터리에 임시 파일을 만들려 하자 `EPERM` 으로 거부됐다.
샌드박스가 권한을 주는 대상은 **드롭된 항목 자신**이지 그 부모가 아니다.

따라서 **4.5(ZipWriter)와 4.6(ZipCleaner)의 "원본 옆에 만든다"는 샌드박스에서 성립하지 않는다.**
결과물의 저장 위치는 항상 `NSSavePanel` 로 사용자에게 묻는다. 사용자가 고른 경로에는
권한이 부여되므로 이 경로만이 두 배포 형태 모두에서 확실히 동작한다.

`ZipCleaner.defaultDestination(for:)` 는 삭제하지 않는다. 저장 패널의 기본 파일명
(`원본이름-정리됨.zip`)을 제안하는 용도로 남긴다. 다만 **그 경로에 직접 쓰지 않는다.**

비샌드박스(Developer ID) 빌드에서는 원본 옆 쓰기가 가능하지만, 두 빌드의 동작을 갈라
놓으면 검증할 표면이 두 배가 된다. **양쪽 모두 저장 패널을 쓴다.**

## 11. 범위 밖 (1.0에서 하지 않음)

- Finder 확장 (우클릭 → "모아쓰기") — 1.1
- 폴더 감시 자동 변환 — 전체 디스크 접근 권한과 백그라운드 상주가 필요해 비용 대비 효용이 나쁨
- 변환 되돌리기(undo) — NFD와 NFC는 화면에 동일하게 보여 되돌릴 대상을 식별할 수 없고,
  파일 내용을 건드리지 않아 복구의 실익이 낮다. 500개 임계값 확인으로 대체한다
- CLI 도구 — 1.0 범위를 넘김
- NFC → NFD 역방향 변환
