#!/usr/bin/env python3
"""App Store Connect 에 실제로 저장된 모아의 상태를 읽어 로컬 원본과 대조한다.

읽기 전용이다. 문구 수정·빌드 선택·심사 제출은 콘솔에서 하고(apple-app-listing,
apple-app-submit 스킬), 이 도구로 "저장됐는가"를 확인한다. 콘솔 화면의 Save 표시나
글자 수만으로는 저장 여부를 믿을 수 없어서 — 줄바꿈 하나가 빠져도 길이는 비슷하다 —
필드 전체를 문자 단위로 비교한다.

사용:
  Scripts/asc.py status              # 버전·빌드·심사 상태
  Scripts/asc.py diff                # store.config.json ↔ 콘솔 저장값 비교
  Scripts/asc.py pull                # 콘솔 저장값을 config 모양의 JSON 으로 출력

`cryptography` 패키지가 필요하다 (JWT ES256 서명).
"""
import argparse
import base64
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "docs/app-store/store.config.json"
API = "https://api.appstoreconnect.apple.com/v1/"

# 이 상태의 버전만 콘솔에서 문구를 고칠 수 있다. 나머지는 기록 확인용이다.
EDITABLE = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
    "METADATA_REJECTED", "INVALID_BINARY",
}
LISTING_FIELDS = ("description", "keywords", "promotionalText", "whatsNew", "supportUrl", "marketingUrl")
APP_INFO_FIELDS = ("name", "subtitle", "privacyPolicyUrl")
# 전화번호는 공개 저장소에 두지 않으므로 비교하지 않는다.
REVIEW_FIELDS = ("contactFirstName", "contactLastName", "contactEmail", "demoAccountRequired", "notes")


def load_config():
    with open(CONFIG, encoding="utf-8") as fh:
        return json.load(fh)


def token(cfg):
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

    key_cfg = cfg["ascApiKey"]
    path = Path(key_cfg["path"]).expanduser()
    if not path.exists():
        sys.exit(f"API 키가 없다: {path}\n  ~/.moa-signing 에 사본이 있으면 복사한다.")
    key = serialization.load_pem_private_key(path.read_bytes(), None)

    def b64(raw):
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    now = int(time.time())
    head = b64(json.dumps({"alg": "ES256", "kid": key_cfg["keyId"], "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": key_cfg["issuerId"], "iat": now, "exp": now + 600,
                           "aud": "appstoreconnect-v1"}).encode())
    r, s = decode_dss_signature(key.sign(f"{head}.{body}".encode(), ec.ECDSA(hashes.SHA256())))
    return f"{head}.{body}.{b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


class Client:
    def __init__(self, cfg):
        self.auth = "Bearer " + token(cfg)

    def get(self, path):
        req = urllib.request.Request(API + path, headers={"Authorization": self.auth})
        try:
            with urllib.request.urlopen(req) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as err:
            sys.exit(f"GET {path} → HTTP {err.code}\n{err.read().decode()[:600]}")


def find_version(api, cfg, version):
    app_id = cfg["app"]["appleId"]
    platform = cfg["app"]["platform"]
    data = api.get(f"apps/{app_id}/appStoreVersions?filter[platform]={platform}"
                   f"&filter[versionString]={version}&include=build")
    if not data["data"]:
        sys.exit(f"콘솔에 {platform} {version} 버전이 없다. 콘솔에서 새 버전을 먼저 만든다.")
    ver = data["data"][0]
    build = next((x for x in data.get("included", []) if x["type"] == "builds"), None)
    return ver, build


def editable_app_info(api, cfg):
    """앱 정보(이름·부제)는 버전과 따로 있다. 고칠 수 있는 쪽이 있으면 그쪽을 본다."""
    infos = api.get(f"apps/{cfg['app']['appleId']}/appInfos?include=appInfoLocalizations")
    items = infos["data"]
    pick = next((i for i in items if i["attributes"]["state"] != "READY_FOR_DISTRIBUTION"), items[0])
    locs = {x["attributes"]["locale"]: x["attributes"] for x in infos.get("included", [])
            if x["type"] == "appInfoLocalizations" and x["id"] in
            {r["id"] for r in pick["relationships"]["appInfoLocalizations"]["data"]}}
    return pick, locs


def remote_state(api, cfg, version):
    ver, build = find_version(api, cfg, version)
    locs = api.get(f"appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]
    listings, shots = {}, {}
    for loc in locs:
        attrs = loc["attributes"]
        listings[attrs["locale"]] = {f: attrs.get(f) for f in LISTING_FIELDS}
        sets = api.get(f"appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
        for s in sets:
            items = api.get(f"appScreenshotSets/{s['id']}/appScreenshots")["data"]
            shots.setdefault(attrs["locale"], {})[s["attributes"]["screenshotDisplayType"]] = [
                {"fileName": i["attributes"]["fileName"],
                 "md5": i["attributes"].get("sourceFileChecksum"),
                 "size": [i["attributes"]["imageAsset"]["width"], i["attributes"]["imageAsset"]["height"]],
                 "state": i["attributes"]["assetDeliveryState"]["state"]}
                for i in items]
    review = api.get(f"appStoreVersions/{ver['id']}/appStoreReviewDetail")["data"]
    review = {f: review["attributes"].get(f) for f in REVIEW_FIELDS} if review else {}
    info, info_locs = editable_app_info(api, cfg)
    app_info = {loc: {f: a.get(f) for f in APP_INFO_FIELDS} for loc, a in info_locs.items()}
    return {
        "version": ver["attributes"]["versionString"],
        "versionState": ver["attributes"]["appStoreState"],
        "releaseType": ver["attributes"]["releaseType"],
        "build": build["attributes"]["version"] if build else None,
        "appInfoState": info["attributes"]["state"],
        "appInfo": app_info,
        "listings": listings,
        "screenshots": shots,
        "review": review,
    }


def sig(text):
    """apple-app-listing/scripts/field-sig.py 와 같은 지문 — 콘솔 화면과 대조할 때 쓴다."""
    buf = text.encode("utf-16-le")
    units = [int.from_bytes(buf[i:i + 2], "little") for i in range(0, len(buf), 2)]
    total = poly = 0
    i = 0
    while i < len(units):
        c = units[i]
        if 0xD800 <= c <= 0xDBFF and i + 1 < len(units) and 0xDC00 <= units[i + 1] <= 0xDFFF:
            c = 0x10000 + ((c - 0xD800) << 10) + (units[i + 1] - 0xDC00)
        total += c
        poly = (poly * 31 + c) % 1000000007
        i += 1
    return f"len={len(units)} sum={total} poly={poly}"


def first_difference(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return min(len(a), len(b))


def compare(label, local, remote, problems):
    if local == remote:
        print(f"  OK    {label}")
        return
    problems.append(label)
    print(f"  DIFF  {label}")
    if isinstance(local, str) and isinstance(remote, str):
        at = first_difference(local, remote)
        print(f"        로컬 {sig(local)}\n        콘솔 {sig(remote)}")
        print(f"        {at}번째 글자부터 다름: 로컬 {local[at:at + 30]!r} / 콘솔 {remote[at:at + 30]!r}")
    else:
        print(f"        로컬 {local!r}\n        콘솔 {remote!r}")


def cmd_status(api, cfg, _args):
    app_id = cfg["app"]["appleId"]
    app = api.get(f"apps/{app_id}")["data"]["attributes"]
    print(f"{app['name']} | {app['bundleId']} | Apple ID {app_id} | 기본 언어 {app['primaryLocale']}")
    print("\n버전")
    vers = api.get(f"apps/{app_id}/appStoreVersions?include=build&limit=10")
    builds = {b["id"]: b["attributes"]["version"] for b in vers.get("included", []) if b["type"] == "builds"}
    for v in vers["data"]:
        a = v["attributes"]
        rel = v["relationships"]["build"]["data"]
        mark = "  ← 편집 가능" if a["appStoreState"] in EDITABLE else ""
        print(f"  {a['platform']} {a['versionString']:<6} {a['appStoreState']:<24} "
              f"출시 {a['releaseType']:<15} 빌드 {builds.get(rel['id']) if rel else '-'}{mark}")
    print("\n최근 빌드")
    for b in api.get(f"builds?filter[app]={app_id}&sort=-uploadedDate&limit=5")["data"]:
        a = b["attributes"]
        print(f"  {a['version']:<6} {a['processingState']:<10} 업로드 {a['uploadedDate']}"
              f"{'  (만료)' if a['expired'] else ''}")
    print("\n심사 제출")
    for s in api.get(f"apps/{app_id}/reviewSubmissions?limit=5")["data"]:
        a = s["attributes"]
        print(f"  {a['platform']} {a['state']:<22} 제출 {a.get('submittedDate') or '-'}  ({s['id']})")


def cmd_pull(api, cfg, args):
    state = remote_state(api, cfg, args.version or cfg["version"])
    json.dump(state, sys.stdout, ensure_ascii=False, indent=2)
    print()


def cmd_diff(api, cfg, args):
    version = args.version or cfg["version"]
    remote = remote_state(api, cfg, version)
    problems = []
    print(f"{cfg['app']['platform']} {version}: 콘솔 상태 {remote['versionState']}, "
          f"선택된 빌드 {remote['build'] or '없음'}, 앱 정보 {remote['appInfoState']}")

    print("\n버전·빌드·출시 방식")
    compare("build", cfg["build"], remote["build"], problems)
    compare("releaseType", cfg["releaseType"], remote["releaseType"], problems)

    print("\n앱 정보")
    for loc, fields in cfg["appInfo"].items():
        for f in APP_INFO_FIELDS:
            compare(f"{loc}.{f}", fields.get(f), remote["appInfo"].get(loc, {}).get(f), problems)
    for loc in sorted(set(remote["appInfo"]) - set(cfg["appInfo"])):
        compare(f"{loc} (콘솔에만 있는 언어)", None, loc, problems)

    print("\n버전 문구")
    for loc, fields in cfg["listings"].items():
        for f in LISTING_FIELDS:
            compare(f"{loc}.{f}", fields.get(f), remote["listings"].get(loc, {}).get(f), problems)
    for loc in sorted(set(remote["listings"]) - set(cfg["listings"])):
        compare(f"{loc} (콘솔에만 있는 언어)", None, loc, problems)

    # 콘솔은 업로드한 파일의 MD5 를 sourceFileChecksum 으로 돌려준다. 콘솔에서 내려받은
    # 사본은 다시 인코딩돼 MD5 가 다르므로, 그런 파일은 업로드 당시 값을 ascChecksum 에 적어 둔다.
    print("\n스크린샷 (순서·파일명·체크섬)")
    for loc, groups in cfg["screenshots"].items():
        for kind, entries in groups.items():
            local = []
            for entry in entries:
                path = ROOT / entry["file"]
                md5 = entry.get("ascChecksum")
                if md5 is None:
                    md5 = hashlib.md5(path.read_bytes()).hexdigest() if path.exists() else "(파일 없음)"
                local.append({"fileName": path.name, "md5": md5})
            got = [{"fileName": x["fileName"], "md5": x["md5"]}
                   for x in remote["screenshots"].get(loc, {}).get(kind, [])]
            compare(f"{loc}.{kind} {len(local)}장", local, got, problems)
            for x in remote["screenshots"].get(loc, {}).get(kind, []):
                if x["state"] != "COMPLETE":
                    problems.append(f"{loc}.{kind}.{x['fileName']}")
                    print(f"  WAIT  {x['fileName']} 처리 상태 {x['state']}")

    print("\n심사 정보")
    for f in REVIEW_FIELDS:
        compare(f"review.{f}", cfg["review"].get(f), remote["review"].get(f), problems)

    print("\n콘솔에서만 확인 가능 (API 없음): App Privacy 공개, 가격·판매 지역")
    if problems:
        print(f"\n불일치 {len(problems)}건. 콘솔에 저장했는데 다르면 다시 열어 확인한다.")
        sys.exit(1)
    print("\n전부 일치.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status", help="버전·빌드·심사 상태")
    for name, help_text in (("diff", "store.config.json 과 콘솔 저장값 비교"),
                            ("pull", "콘솔 저장값을 JSON 으로 출력")):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--version", help="대상 버전 (기본: store.config.json 의 version)")
    args = parser.parse_args()
    cfg = load_config()
    api = Client(cfg)
    {"status": cmd_status, "pull": cmd_pull, "diff": cmd_diff}[args.cmd](api, cfg, args)


if __name__ == "__main__":
    main()
