# 개인정보 처리방침 / Privacy Policy

**모아 (Moa)** — 최종 수정 2026-08-17

## 한국어

### 수집하는 정보

**없습니다.**

모아는 개인정보를 수집하지 않고, 사용 기록을 남기지 않으며, 어떤 데이터도 외부로 보내지 않습니다.

이건 약속이 아니라 구조적으로 불가능한 것입니다. 모아는 App Sandbox 안에서 동작하고 네트워크 권한(`com.apple.security.network.client`)을 요청하지 않습니다. macOS가 이 앱의 모든 네트워크 연결을 차단합니다. 분석 도구나 크래시 리포터도 넣지 않았습니다.

앱에 포함된 외부 라이브러리는 ZIP 압축을 담당하는 [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 하나뿐이며, 이 역시 네트워크를 쓰지 않습니다.

### 파일 접근

모아는 **사용자가 직접 끌어다 놓거나 파일 선택 창에서 고른 파일과 폴더**만 읽고 씁니다. 그 밖의 위치에는 접근할 수 없습니다 — 이것도 App Sandbox가 강제합니다.

파일의 내용은 읽지 않습니다. 파일명만 읽고 고칩니다. ZIP으로 묶을 때만 내용을 읽으며, 이때도 사용자가 지정한 위치에 쓰는 것 외에는 아무 데도 보내지 않습니다.

### 제3자 제공

제공할 데이터가 없으므로 제3자에게 제공하는 것도 없습니다.

### 문의

[GitHub Issues](https://github.com/clichedmoog/Moa/issues)로 남겨주세요.

---

## English

### Data collection

**None.**

Moa collects no personal information, keeps no usage records, and transmits no data anywhere.

This is structural rather than a promise. Moa runs inside the App Sandbox and does not request the network entitlement (`com.apple.security.network.client`), so macOS blocks every outbound connection the app could attempt. No analytics or crash-reporting SDK is bundled.

The only third-party library included is [ZIPFoundation](https://github.com/weichsel/ZIPFoundation), used for ZIP archiving. It does not use the network either.

### File access

Moa reads and writes only the files and folders you explicitly drag onto it or choose in an open panel. It cannot reach anything else — the App Sandbox enforces this.

Moa does not read file contents; it reads and corrects filenames. Contents are read only when creating a ZIP archive, and even then the result goes solely to the location you choose.

### Third parties

There is no data to share, so nothing is shared.

### Contact

Please open a [GitHub Issue](https://github.com/clichedmoog/Moa/issues).
