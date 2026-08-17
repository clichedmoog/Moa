# 모아 (Moa) — 핸드오프

작성일: 2026-08-14

> ⚠️ **이 문서는 2026-08-14 시점의 기록이며, 일부 내용이 실측으로 반증됐다.**
> 최신 기준은 [`docs/superpowers/specs/2026-08-16-moa-design.md`](docs/superpowers/specs/2026-08-16-moa-design.md)다.
> 특히 5번의 exFAT 거동(실제로는 NFD 강제)과 7번의 "Java 기반"(실제로는 Swift)은 틀렸다.
> 5번의 ⚠️ 실측 항목은 해소됐다 — APFS는 임시 이름 경유가 불필요하다.

## 1. 한 줄 요약

macOS에서 자소분리(유니코드 NFD)된 한글 파일명을 NFC로 정규화해주는 macOS 앱.

## 2. 현재 상태

- 저장소: https://github.com/clichedmoog/Moa (**private**)
- 로컬: `/Users/tenma/Development/GitHub/Moa`
- `main` 브랜치, 커밋 1개 — `README.md`, `.gitignore`
- **코드는 아직 없음.** Xcode 프로젝트 생성이 첫 작업이다.

## 3. 확정된 결정

| 항목 | 결정 |
| --- | --- |
| 앱 이름 | 모아 (Moa) — "풀어쓰기(NFD) → 모아쓰기(NFC)"에서 따옴 |
| 배포 방식 | Developer ID 서명 + 공증(notarization) 후 직접 배포 |
| 아키텍처 | Apple Silicon 네이티브 (로제타 불필요) |
| Apple 계정 | Apple Developer Program 가입 상태 (iOS 개발자) → Developer ID Application 인증서 발급 가능 |
| 저장소 공개 여부 | 일단 private. 공개 전환은 `gh repo edit --visibility public` |

## 4. 미결정 — 다음 세션에서 먼저 정할 것

1. **앱 형태**
   - A. 드래그앤드롭 창 하나 (선행 앱 Contact와 동일)
   - B. A + Finder 확장 (우클릭 → "모아쓰기")
   - C. B + 폴더 감시 자동 변환
   - 추천: **A로 1.0을 내고 B를 다음 버전에.** C는 전체 디스크 접근 권한과 백그라운드 상주가 필요해 비용 대비 효용이 급격히 나빠진다.
2. **Mac App Store 병행 여부** — 샌드박스 제약 탓에 B/C가 어려워진다. 직접 배포만 하는 쪽을 추천.
3. 변환 되돌리기(undo) 제공 여부. 파일명을 바꾸는 앱이라 실수 복구 수단이 있으면 신뢰도가 올라간다.
4. 번들 ID (`com.clichedmoog.Moa` 등), 최소 지원 macOS 버전.

## 5. 기술 배경 — 구현 전에 반드시 읽을 것

### 핵심 변환

Swift 표준 API 한 줄로 끝난다.

- NFC(모아쓰기): `str.precomposedStringWithCanonicalMapping`
- NFD(풀어쓰기): `str.decomposedStringWithCanonicalMapping`

어려운 건 변환이 아니라 **파일시스템 위에서 안전하게 이름을 바꾸는 부분**이다.

### 재귀 처리 순서

디렉터리 트리를 순회하며 이름을 바꿀 때는 **깊은 항목부터(bottom-up)** 처리해야 한다. 부모 폴더 이름을 먼저 바꾸면 미리 수집해둔 자식 경로가 전부 무효가 된다.

### 파일시스템별 거동

| 파일시스템 | 거동 |
| --- | --- |
| HFS+ | 파일명을 강제로 NFD(애플 변형)로 정규화해 저장. **NFC로 바꿔도 다시 NFD가 되므로 변환이 무의미하다.** |
| APFS | 저장한 형태를 그대로 보존(normalization-preserving). 단, 비교는 정규화를 무시(normalization-insensitive)하므로 NFD 이름과 NFC 이름을 같은 파일로 취급한다. |
| exFAT / FAT32 / NTFS | 저장한 그대로 보존. 여기로 옮길 때 NFC 변환의 효과가 가장 크다. |

> ⚠️ **실측이 필요한 지점**: APFS는 NFD와 NFC를 동일한 이름으로 비교하기 때문에, `FileManager.moveItem`으로 NFD→NFC rename을 시도하면 "이미 존재함" 에러가 나거나 조용히 무시될 가능성이 있다. 임시 이름을 경유하는 2단계 rename(원본 → 임시 → NFC)이 필요한지 **코드를 쓰기 전에 작은 스크립트로 먼저 확인할 것.** 여기서 어떤 결과가 나오느냐가 코어 로직 설계를 좌우한다.

### 그 밖의 구현 주의점

- 이미 NFC인 항목은 건너뛴다. 불필요한 rename으로 수정 시각이 바뀌는 걸 막는다.
- `precomposedStringWithCanonicalMapping`은 한글뿐 아니라 모든 문자에 적용된다(일본어 탁점 등도 같은 문제를 겪는다). 전체에 적용할지 한글만 골라낼지 정할 것 — 전체 적용이 기본값으로 무난하다.
- 이름 충돌 시 정책 필요 (건너뛰기 / 번호 붙이기 / 사용자에게 묻기).
- 심볼릭 링크는 따라가지 않는다.
- `.app`, `.rtfd` 같은 번들 패키지는 디렉터리지만 내부를 건드리지 않는 편이 안전하다.
- 대상 볼륨이 HFS+면 변환이 무의미하므로, 감지해서 사용자에게 알려주는 편이 친절하다.

## 6. 서명·공증 절차 (계정 보유)

1. Developer ID Application 인증서 발급 — Xcode > Settings > Accounts, 또는 developer.apple.com
2. Xcode의 Signing & Capabilities에서 Developer ID로 서명, **Hardened Runtime 활성화** (공증 필수 조건)
3. `xcrun notarytool store-credentials "MOA_NOTARY"` 로 App Store Connect API 키(또는 앱 전용 암호)를 키체인 프로파일로 저장
4. `xcrun notarytool submit Moa.zip --keychain-profile "MOA_NOTARY" --wait`
5. `xcrun stapler staple Moa.app` 후 DMG로 묶어 배포

자격 증명은 절대 커밋하지 않는다 — `.gitignore`에 `*.p12`, `*.provisionprofile`, `.env`를 이미 등록해뒀다.

## 7. 선행 앱 — Contact

- 김남호 님, 2020년 제작, 오픈소스, 드래그앤드롭 방식 — https://namocom.tistory.com/901
- 이름 유래는 코로나 시절 "언택트"의 반대말. 흩어진 자모를 다시 접촉시킨다는 뜻.
- **한계**: 코드 사이닝 없음(첫 실행 시 보안 경고), ~~Java 기반이라~~ Apple Silicon에서 로제타 필요
  - **정정**: Java 가 아니라 Swift + Cocoa 다. 로제타가 필요한 이유는 배포 바이너리가
    `Mach-O thin x86_64`(인텔 전용 빌드)이기 때문. 언어가 아니라 빌드 대상의 문제였다.
- 우리 차별점은 정확히 이 두 가지 — **서명·공증 + 네이티브**
- UX는 참고할 만하다: 창에 드래그앤드롭, 드롭이 어려운 사용자를 위해 hover 시 파일 선택 버튼 노출

## 8. 다음 액션 체크리스트

- [ ] 앱 형태 결정 (4번 1항)
- [ ] APFS rename 거동 실측 (5번 ⚠️)
- [ ] Xcode 프로젝트 생성 (SwiftUI, macOS, 번들 ID 확정)
- [ ] 변환 코어 로직 + 단위 테스트 (NFD 파일명 픽스처를 코드로 생성해 검증)
- [ ] 드래그앤드롭 UI
- [ ] 서명·공증 파이프라인 구축
- [ ] 저장소 public 전환 여부 결정 후 릴리스
