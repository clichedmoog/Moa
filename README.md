# 모아 (Moa)

맥에서 자소분리된 한글 파일명을 고쳐주는 macOS 앱.

## 문제

macOS는 파일명을 유니코드 **NFD**(풀어쓰기) 형태로 저장한다. 그래서 맥에서 만든 `한글.txt`를 압축해서 옮기거나 Windows·Linux·DLNA 기기·일부 클라우드에서 열면 `ㅎㅏㄴㄱㅡㄹ.txt`처럼 자모가 흩어져 보인다.

## 해결

파일·폴더를 창에 끌어다 놓으면 파일명을 **NFC**(모아쓰기)로 정규화한다. 앱 이름 그대로 흩어진 자모를 다시 모아쓰는 일을 한다.

## 목표

- Apple Silicon 네이티브 (로제타 불필요)
- 코드 사이닝 + 공증(notarization) — 첫 실행에 보안 경고를 뚫을 필요 없이 그냥 열림
- 드래그앤드롭 한 번으로 끝나는 단순한 동작

## 설치

[Releases](https://github.com/clichedmoog/Moa/releases)에서 최신 `Moa-1.0.dmg`를 받아 연다.

Developer ID로 서명하고 공증(notarization)까지 마쳤으므로 첫 실행에 보안 경고 없이 그냥 열린다. Apple Silicon과 Intel 모두 네이티브로 동작한다 (로제타 불필요).

## 알아두면 좋은 것

- **APFS 볼륨에서만 파일명이 고쳐진 채로 유지된다.** HFS+와 exFAT은 macOS 드라이버가 파일명을 자소분리(NFD) 형태로 되돌려 쓰기 때문에, 모아로 NFC로 바꿔도 그 볼륨에 저장하는 순간 다시 풀어진다. 이런 볼륨으로 옮길 때는 먼저 ZIP으로 묶는다 — ZIP 안의 이름은 파일시스템과 무관하게 그대로 유지된다.
- **맥 기본 압축은 Windows에서 파일명이 깨진다.** `ditto`와 `zip` 같은 macOS 기본 압축 도구는 ZIP의 UTF-8 플래그(general purpose bit 11)를 세우지 않는다. 그러면 Windows 탐색기가 이름을 CP949로 잘못 해석해 깨져 보인다. 모아의 "ZIP으로 묶기" 기능은 이 플래그를 세워서 내보내므로 Windows에서도 이름이 온전하다.

## 참고

같은 문제를 다루는 선행 앱으로 김남호 님의 [Contact](https://namocom.tistory.com/901)([소스](https://github.com/namhokim/cocoa_app), MIT)가 있다. 코드 사이닝이 없고 Java 기반이라 Apple Silicon에서 로제타가 필요한 점을 개선하는 것이 이 프로젝트의 출발점이다. 드래그앤드롭 UX와 마우스를 올렸을 때 파일 선택 버튼이 나타나는 아이디어를 참고했고, 코드는 별도로 작성했다.
