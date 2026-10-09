# Mac App Store 문구 판단 근거

실제 문구는 [store.config.json](store.config.json)에 있고, 콘솔 저장값과 같은지는 `Scripts/asc.py diff`로 확인한다. 이 문서에는 문구를 그렇게 정한 이유만 남긴다. 처음에는 이 파일에 초안을 같이 두었는데, 콘솔에서 해요체로 다듬고 Finder 서비스·단축어 단락을 더한 뒤로 초안과 실제 값이 갈라졌다. 원본을 두 군데 두지 않으려고 문구는 config로 옮겼다.

## 왜 문구에 공을 들이는가

이 앱은 발견 가능성이 곧 배포다. "자소분리", "한글 파일명 깨짐"으로 검색하는
사람에게 걸리지 않으면 아무도 이 앱의 존재를 모른다. GitHub Release는 이미
저장소를 찾은 사람에게만 닿는다.

ASO 가중치는 **이름 > 부제 > 키워드** 순이라, 검색어를 이름과 부제에 먼저 넣고
남는 것을 키워드 필드로 넘긴다. 키워드 필드에 이름·부제에 이미 쓴 단어를 다시
넣는 건 낭비다. Apple은 이름·부제·키워드를 합쳐서 색인한다.

- 이름 `모아 - 한글 파일명 복구`, 부제 `자소분리 고치고 윈도우용 ZIP까지`
- 이름·부제에 이미 들어간 "모아 / 한글 / 파일명 / ZIP"은 키워드에서 뺐다.
- 부제는 버전 페이지가 아니라 "앱 정보" 페이지에 있다.
- 프로모션 텍스트는 출시된 버전에서도 심사 없이 바꿀 수 있다.

## 그 밖의 필드

| 필드 | 값 |
| --- | --- |
| 카테고리 | 유틸리티 (`public.app-category.utilities`) |
| 연령 등급 | 4+ |
| 개인정보 처리방침 URL | https://github.com/clichedmoog/Moa/blob/main/docs/privacy.md |
| 지원 URL | https://github.com/clichedmoog/Moa/issues |
| App Privacy 설문 | Data Not Collected — 네트워크 entitlement 자체가 없어 샌드박스가 모든 연결을 막는다 |
| 가격 | 무료 |
| 언어 | 한국어 |

## 심사에서 걸릴 수 있는 것

- **Guideline 4.2 (최소 기능)** — 단일 목적 유틸리티가 "웹사이트로 충분하지
  않냐"로 반려되는 경우가 있다. 1.0은 통과했다. 반려되면 설명과 심사 메모에서
  "OS 기본 도구로는 불가능한 이유"를 더 앞세운다. 심사 메모의
  `WHAT macOS CANNOT DO ON ITS OWN` 단락이 그 역할을 한다.
- **Guideline 3.1.1** — 후원 메뉴는 `ReleaseMAS` 빌드에서 제외한다.
  `Scripts/release-mas.sh`가 바이너리에 후원 링크가 남았는지 검사한다.
- **Guideline 2.1(a)** — 심사관은 자소분리 파일을 눈으로 구분할 수 없다. 샘플
  ZIP과 고정 URL을 유지한다. 경과는 [releases/1.0.md](releases/1.0.md)에 있다.
