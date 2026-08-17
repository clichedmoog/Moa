#!/bin/bash
# GitHub Release용 서명·공증·스테이플·DMG 파이프라인.
#
# 사전 준비 (한 번만, 이미 완료됨):
#   xcrun notarytool store-credentials "MOA_NOTARY"
#
# 실행:
#   ./Scripts/release.sh
#
# .app 과 .dmg 를 각각 독립적으로 공증·스테이플한다 — GateKeeper/stapler는
# 두 아티팩트를 별개로 검사하므로, .app 안에 티켓이 있어도 .dmg 자체에는
# 없다. 따라서 .app을 공증→스테이플한 뒤 그 .app을 담은 .dmg를 만들고,
# .dmg도 서명 후 다시 공증→스테이플한다.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Moa"
VERSION="1.0"
TEAM_ID="N9LYHMUDKA"
SIGN_ID="Developer ID Application: Myeongseok SEO (${TEAM_ID})"
NOTARY_PROFILE="MOA_NOTARY"

# CI 는 서명 키를 기본 로그인 키체인이 아니라 임시 키체인에 둔다.
# MOA_KEYCHAIN 이 설정돼 있으면 notarytool 에 그 키체인을 알려준다.
# 로컬에서는 비어 있으므로 평소대로 로그인 키체인을 쓴다.
KEYCHAIN_ARGS=()
if [ -n "${MOA_KEYCHAIN:-}" ]; then
    KEYCHAIN_ARGS=(--keychain "$MOA_KEYCHAIN")
    echo "── 임시 키체인 사용: $MOA_KEYCHAIN"
fi

BUILD=".build/release-app"
rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "── XcodeGen 재생성"
(cd MoaApp && xcodegen generate)

echo "── 아카이브 (Release)"
xcodebuild -project MoaApp/Moa.xcodeproj \
    -scheme Moa -configuration Release \
    -archivePath "$BUILD/Moa.xcarchive" \
    -destination 'generic/platform=macOS' \
    archive

APP="$BUILD/Moa.xcarchive/Products/Applications/${APP_NAME}.app"

echo "── Universal 바이너리 확인"
lipo -archs "$APP/Contents/MacOS/${APP_NAME}"
lipo -archs "$APP/Contents/MacOS/${APP_NAME}" | grep -q "arm64" || { echo "arm64 누락"; exit 1; }
lipo -archs "$APP/Contents/MacOS/${APP_NAME}" | grep -q "x86_64" || { echo "x86_64 누락"; exit 1; }

echo "── 서명 확인 (.app)"
codesign -dv --verbose=4 "$APP" 2>&1 | tee "$BUILD/codesign-app.log"
grep -q "Developer ID Application" "$BUILD/codesign-app.log" || { echo "서명 아이덴티티가 Developer ID Application이 아니다"; exit 1; }
grep -q "flags=0x10000(runtime)" "$BUILD/codesign-app.log" || { echo "Hardened Runtime 플래그(0x10000)가 없다"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"

# 공증을 제출하고 완료까지 대기한다. 실패 시 상세 로그를 받아 즉시 종료한다.
# (실패를 숨기고 넘어가지 않는다 — 원인을 그대로 보고한다.)
notarize_and_wait () {
    local target="$1"
    local out
    out=$(xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" "${KEYCHAIN_ARGS[@]}" --wait 2>&1)
    echo "$out"

    local sub_id
    sub_id=$(echo "$out" | grep -m1 -E '^[[:space:]]*id:' | awk '{print $2}')
    local status
    status=$(echo "$out" | grep -E '^[[:space:]]*status:' | tail -1 | awk '{print $2}')

    if [[ "$status" != "Accepted" ]]; then
        echo "!! 공증 실패: $target (status=${status:-unknown}, id=${sub_id:-unknown})"
        if [[ -n "${sub_id:-}" ]]; then
            xcrun notarytool log "$sub_id" --keychain-profile "$NOTARY_PROFILE" "${KEYCHAIN_ARGS[@]}" "$BUILD/notary-${sub_id}.log" || true
            echo "── 공증 로그 (notary-${sub_id}.log)"
            cat "$BUILD/notary-${sub_id}.log" || true
        fi
        exit 1
    fi
    echo "공증 성공: $target (id=$sub_id)"
}

echo "── 공증 제출 (.app)"
ditto -c -k --keepParent "$APP" "$BUILD/${APP_NAME}.zip"
notarize_and_wait "$BUILD/${APP_NAME}.zip"

echo "── 스테이플 (.app)"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "── Gatekeeper 확인 (.app)"
spctl -a -vvv -t exec "$APP"

echo "── DMG 생성"
DMG_SRC="$BUILD/dmg"
rm -rf "$DMG_SRC"
mkdir -p "$DMG_SRC"
cp -R "$APP" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications"
DMG_PATH="$BUILD/${APP_NAME}-${VERSION}.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_SRC" -ov -format UDZO "$DMG_PATH"

echo "── DMG 서명"
codesign --sign "$SIGN_ID" --timestamp "$DMG_PATH"
codesign -dv --verbose=4 "$DMG_PATH"

echo "── 공증 제출 (.dmg)"
notarize_and_wait "$DMG_PATH"

echo "── 스테이플 (.dmg)"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo ""
echo "완료: $DMG_PATH"
