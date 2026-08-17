#!/bin/bash
#
# Mac App Store 제출용 .pkg 를 만들고 App Store Connect 에 올린다.
#
# Developer ID 배포(Scripts/release.sh)와 서명 체계가 다르다:
#   Developer ID — Developer ID Application + 공증 + DMG
#   App Store    — Apple Distribution + 프로비저닝 프로파일 + 서명된 .pkg
#
# 사전 준비 (한 번만):
#   1. 인증서 두 장이 키체인에 있어야 한다
#        Apple Distribution: ...
#        3rd Party Mac Developer Installer: ...
#   2. 프로비저닝 프로파일 "Moa Mac App Store" 가 설치돼 있어야 한다
#        ~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile
#   3. 업로드용 앱 암호를 키체인에 넣어둔다 — 인자로 넘기지 않는 이유는
#      명령행 인자가 `ps` 로 다른 프로세스에 보이기 때문이다.
#        security add-generic-password -a "$APPLE_ID" -s MOA_ASC_PASSWORD -w
#      (붙여넣기 프롬프트가 뜬다. 값은 appleid.apple.com 에서 만든 앱 암호)
#
# 사용:
#   Scripts/release-mas.sh              # 빌드 + 검증까지만 (업로드 안 함)
#   Scripts/release-mas.sh --upload     # 빌드 + 검증 + 업로드
#
set -euo pipefail

TEAM_ID="N9LYHMUDKA"
APPLE_ID="tenma@mac.com"
BUNDLE_ID="com.clichedmoog.Moa"
PROFILE_NAME="Moa Mac App Store"
KEYCHAIN_ITEM="MOA_ASC_PASSWORD"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/release-mas"
UPLOAD=0
[ "${1:-}" = "--upload" ] && UPLOAD=1

echo "── 프로젝트 생성"
(cd "$ROOT/MoaApp" && xcodegen generate >/dev/null)

echo "── 사전 점검"
for id in "Apple Distribution" "3rd Party Mac Developer Installer"; do
    if security find-identity -v -p basic | grep -q "$id"; then
        echo "   ✓ $id"
    else
        echo "   ✗ $id 인증서가 키체인에 없다" >&2; exit 1
    fi
done
if ls ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.provisionprofile >/dev/null 2>&1; then
    echo "   ✓ 프로비저닝 프로파일 디렉터리 존재"
else
    echo "   ✗ 프로비저닝 프로파일이 설치돼 있지 않다" >&2; exit 1
fi

rm -rf "$BUILD"; mkdir -p "$BUILD"

echo "── 아카이브 (ReleaseMAS)"
xcodebuild archive \
    -project "$ROOT/MoaApp/Moa.xcodeproj" \
    -scheme Moa \
    -configuration ReleaseMAS \
    -archivePath "$BUILD/Moa.xcarchive" \
    -derivedDataPath "$BUILD/dd" \
    | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" || true

APP="$BUILD/Moa.xcarchive/Products/Applications/Moa.app"
[ -d "$APP" ] || { echo "아카이브 실패" >&2; exit 1; }

echo "── 아카이브 검증"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority=Apple Distribution" >/dev/null \
    && echo "   ✓ Apple Distribution 으로 서명됨" \
    || { echo "   ✗ 서명 주체가 다르다" >&2; exit 1; }
[ -f "$APP/Contents/embedded.provisionprofile" ] \
    && echo "   ✓ 프로파일 임베드됨" \
    || { echo "   ✗ embedded.provisionprofile 없음" >&2; exit 1; }
echo "   ✓ 아키텍처: $(lipo -archs "$APP/Contents/MacOS/Moa")"

# 후원 메뉴가 이 빌드에 남아 있으면 Guideline 3.1.1 로 반려될 수 있다.
if strings "$APP/Contents/MacOS/Moa" | grep -q "sponsors/"; then
    echo "   ✗ 후원 링크가 MAS 빌드에 남아 있다 — #if !MAS 확인" >&2; exit 1
fi
echo "   ✓ 후원 링크 없음 (Guideline 3.1.1)"

echo "── .pkg 내보내기"
cat > "$BUILD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>export</string>
    <key>teamID</key><string>${TEAM_ID}</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Apple Distribution</string>
    <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>
    <key>provisioningProfiles</key>
    <dict><key>${BUNDLE_ID}</key><string>${PROFILE_NAME}</string></dict>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$BUILD/Moa.xcarchive" \
    -exportPath "$BUILD/export" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" \
    | grep -E "error:|EXPORT (SUCCEEDED|FAILED)" || true

PKG="$BUILD/export/Moa.pkg"
[ -f "$PKG" ] || { echo "내보내기 실패" >&2; exit 1; }
echo "   ✓ $PKG ($(( $(stat -f%z "$PKG") / 1024 )) KB)"

if ! security find-generic-password -s "$KEYCHAIN_ITEM" >/dev/null 2>&1; then
    echo
    echo "앱 암호가 키체인에 없어 검증·업로드를 건너뛴다. 넣으려면:"
    echo "  security add-generic-password -a \"$APPLE_ID\" -s $KEYCHAIN_ITEM -w"
    echo
    echo "빌드는 끝났다: $PKG"
    exit 0
fi

echo "── App Store Connect 검증"
xcrun altool --validate-app -f "$PKG" -t macos \
    -u "$APPLE_ID" -p "@keychain:$KEYCHAIN_ITEM" 2>&1 | sed 's/^/   /'

if [ "$UPLOAD" -eq 1 ]; then
    echo "── 업로드"
    xcrun altool --upload-app -f "$PKG" -t macos \
        -u "$APPLE_ID" -p "@keychain:$KEYCHAIN_ITEM" 2>&1 | sed 's/^/   /'
    echo
    echo "업로드 완료. App Store Connect 에서 처리가 끝나면(보통 10~30분)"
    echo "빌드를 버전에 붙이고 심사에 제출한다."
else
    echo
    echo "검증까지 끝났다. 올리려면: Scripts/release-mas.sh --upload"
fi
