# 모아 Mac App Store 출시

Mirror 저장소에서 정리한 iOS·macOS 공용 출시 스킬 세 개를 `.agents/skills/`에 가져왔다(Codex용 원본). `.claude/skills/`에는 같은 폴더를 가리키는 심볼릭 링크를 두어 Claude Code에서도 같은 스킬을 쓴다. 스킬에는 앱 정보가 없고, 이 문서와 [store.config.json](store.config.json)에서 읽는다.

| 할 일 | 스킬 | 요청 예 |
| --- | --- | --- |
| 스토어 문구·스크린샷 변경 | [apple-app-listing](../../.agents/skills/apple-app-listing/SKILL.md) | `apple-app-listing으로 모아 설명을 바꿔줘` |
| 서명된 빌드·실행 확인 | [apple-app-build-prod](../../.agents/skills/apple-app-build-prod/SKILL.md) | `apple-app-build-prod로 1.1 (3) 빌드해줘` |
| 업로드·심사 제출 | [apple-app-submit](../../.agents/skills/apple-app-submit/SKILL.md) | `apple-app-submit으로 1.1 심사 넣어줘` |

## 대상 앱

| 항목 | 값 |
| --- | --- |
| 플랫폼 | macOS 전용 (Mac App Store). iOS·Mac Catalyst 대상 없음 |
| App Store ID | `6802254516` |
| 번들 ID / SKU | `com.clichedmoog.Moa` / `MOA-MACOS-001` |
| 팀 | Myeongseok SEO / `N9LYHMUDKA` (개인) |
| Scheme / 구성 | `Moa` / `ReleaseMAS` (`Release`는 Developer ID·DMG용) |
| 프로파일 | `Moa Mac App Store` |
| API 키 | `DF5M8R379V` (`~/.appstoreconnect/private_keys/`, 사본 `~/.moa-signing`) |
| 스토어 언어 | 한국어만 (기본 언어 `ko`) |

브라우저로 App Store Connect를 열면 계정 선택이 회사 팀(Babaground, Inc.)으로 잡히는 일이 잦다. 작업 전에 **Myeongseok SEO**로 바꾼다.

## 원본과 확인

[store.config.json](store.config.json)이 콘솔에 들어갈 값의 원본이다. 앱 이름·부제·설명·키워드·프로모션 텍스트·업데이트 내용·URL·스크린샷 순서·심사 메모가 여기에 있다. 2026-10-09에 콘솔 저장값을 그대로 받아와 만들었고, 문구를 다시 타이핑하지 않았다. 심사 연락처 전화번호는 공개 저장소라 넣지 않았고, 콘솔 값을 그대로 둔다.

`Scripts/asc.py`는 App Store Connect API로 콘솔의 실제 저장값을 읽는다. 쓰기 기능은 없다.

```sh
Scripts/asc.py status                # 버전·빌드·심사 상태
Scripts/asc.py diff                  # store.config.json ↔ 콘솔, 필드 전체를 문자 단위로 비교
Scripts/asc.py diff --version 1.1    # 다른 버전과 비교
Scripts/asc.py pull                  # 콘솔 값을 JSON으로 출력 (config 갱신용)
```

`cryptography` 패키지가 필요하다. `diff`가 비교하지 않는 항목은 콘솔에서 직접 본다: App Privacy("데이터를 수집하지 않음"), 연령 등급, 가격(무료)·판매 지역. 이 값들은 config의 `consoleOnly`에 기록만 해 둔다.

## 문구 바꾸기

1. `store.config.json`의 해당 필드를 고친다. 제한: 이름·부제 30자, 키워드 100자(쉼표 구분·공백 없이. 현재 80자·UTF-8 178바이트로 저장돼 있어 바이트가 아니라 글자 기준이다), 프로모션 텍스트 170자, 설명 4000자.
2. **프로모션 텍스트**는 심사 없이 출시된 버전에서도 바로 고칠 수 있다. 나머지 버전 문구는 편집 가능한 새 버전(`PREPARE_FOR_SUBMISSION` 등)이 있어야 하고, 이름·부제는 새 버전과 함께 심사받는다.
3. `apple-app-listing` 스킬로 콘솔에 붙여 넣는다. 파일에서 읽어 넣고, 손으로 다시 치지 않는다.
4. `Scripts/asc.py diff`로 저장값이 원본과 같은지 확인한다.

ASO 판단 근거(이름 > 부제 > 키워드 가중치, 키워드 중복 금지)는 [metadata.md](metadata.md)에 있다.

## 스크린샷

macOS용 `APP_DESKTOP` 그룹 하나, 2560×1600 PNG 3장이다. 2026-10-09 콘솔 표시 순서는 **03-zip → 02-result → 01-idle**이고, config도 이 순서로 기록했다.

`screenshots/`의 PNG는 2026-10-09에 콘솔에서 내려받은 사본이다. 이전 커밋의 파일은 합쇼체 문구("됩니다")였고, 실제로 올라간 것은 해요체("돼요")판이라 사본으로 교체했다. 해요체 원본 파일은 찾지 못했다. 내려받은 사본은 다시 인코딩된 것이라 MD5가 업로드 당시 값과 다르다. 그래서 config의 `ascChecksum`에 콘솔이 알려 준 업로드 당시 값을 적어 두었다. 새 이미지를 올릴 때는 `ascChecksum`을 지운다. 그러면 `diff`가 로컬 파일의 MD5와 콘솔 값을 직접 비교한다.

캡처 방법(실제 앱 창을 `screencapture -l`로 찍어 2560×1600 캔버스에 합성, 결과 화면은 자소분리 파일 8개를 실제로 처리한 것)은 커밋 `96c3e14`에 적혀 있다. 합성 스크립트는 저장소에 없다. Mac 스크린샷에 iPhone 프레임을 씌우거나 화면을 늘리지 않는다.

## 빌드와 업로드

```sh
Scripts/release-mas.sh            # 아카이브·서명 검증·.pkg·altool 검증까지 (업로드 안 함)
Scripts/release-mas.sh --upload   # 업로드까지
```

스크립트가 확인하는 것: Apple Distribution 서명, 임베드된 프로파일, Universal 아키텍처, 후원 링크 제외(Guideline 3.1.1), 아카이브 버전·빌드가 config의 `version`·`build`와 같은지. 업로드한 버전·빌드 쌍은 덮어쓸 수 없으므로 올리기 전에 `Scripts/asc.py status`로 기존 빌드 번호를 확인한다.

**새 버전을 낼 때 바꿀 곳**

- `MoaApp/project.yml`: `CFBundleShortVersionString`·`MARKETING_VERSION`(버전), `CFBundleVersion`·`CURRENT_PROJECT_VERSION`(빌드). 두 쌍이 같아야 한다.
- `docs/app-store/store.config.json`: `version`, `build`, 새 `whatsNew`
- Developer ID 배포를 같이 할 때: `Scripts/release.sh`의 `VERSION`, README의 DMG 파일명

Mac에서 확인할 것: ReleaseMAS 빌드를 실행해 파일·폴더·ZIP 드롭, Dock 드롭, Finder 서비스 "모아쓰기", 단축어 액션, 샌드박스 안에서 사용자가 고른 위치에 ZIP 저장. Developer ID 빌드나 Debug 실행은 App Store 서명·샌드박스 검증을 대신하지 못한다.

## 심사

- **심사용 샘플 파일**: 심사 메모가 `https://github.com/clichedmoog/Moa/raw/main/docs/app-store/moa-review-samples.zip`을 가리킨다. Apple이 "앞으로의 심사에도 남아 있을 위치"를 요구했으므로 이 파일을 **옮기거나 이름을 바꾸지 않는다**. 1.0이 2.1(a)로 반려된 이유가 이 샘플이 없었던 것이다.
- 기능을 더하면 심사 메모의 TEST 항목과 샘플 ZIP 안의 `READ ME FIRST.txt`도 함께 고친다.
- 로그인·데모 계정은 필요 없다(`demoAccountRequired: false`).
- **출시 방식**: 1.0은 `AFTER_APPROVAL`(승인 즉시 자동 출시)이었다. 공용 스킬은 지정이 없으면 수동 출시를 고르므로, 버전마다 config의 `releaseType`을 정하고 콘솔에서 같은 값인지 확인한다.
- 심사 대기 시간: macOS는 심사 시작까지 5~7일이 정상 범위였다(1.0 첫 제출 8/17 → 반려 8/25).

출시 기록은 [releases/](releases/)에 버전별로 남긴다. `.pkg`, 아카이브, `.p8`·`.p12`는 커밋하지 않는다.
