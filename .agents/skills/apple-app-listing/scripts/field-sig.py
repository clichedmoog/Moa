#!/usr/bin/env python3
"""Fingerprint a listing field so a console paste can be verified character-for-character.

`len` counts UTF-16 units, and surrogate pairs are recombined, so every number here
matches iterating `String.prototype.codePointAt` in the browser. Why a fingerprint
rather than a length: see the app-listing skill, "Pull the copy from the file — never retype it".
"""
import json
import sys


def sig(text):
    buf = text.encode("utf-16-le")
    units = [int.from_bytes(buf[i : i + 2], "little") for i in range(0, len(buf), 2)]
    total = poly = 0
    n = len(units)
    for i in range(n):
        c = units[i]
        if 0xD800 <= c <= 0xDBFF and i + 1 < n and 0xDC00 <= units[i + 1] <= 0xDFFF:
            c = 0x10000 + ((c - 0xD800) << 10) + (units[i + 1] - 0xDC00)
        total += c
        poly = (poly * 31 + c) % 1000000007
    return {"len": n, "sum": total, "poly": poly}


def head(text, units=20):
    """First `units` UTF-16 units, matching the browser's `v.slice(0, 20)`."""
    return text.encode("utf-16-le")[: units * 2].decode("utf-16-le", errors="ignore")


def dig(obj, path):
    walked = []
    for key in path.split("."):
        if not isinstance(obj, dict) or key not in obj:
            sys.exit(
                f"'{'.'.join(walked) or '(root)'}' 아래에 '{key}' 가 없다.\n"
                f"  있는 키: {list(obj) if isinstance(obj, dict) else type(obj).__name__}"
            )
        obj = obj[key]
        walked.append(key)
    return obj


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(
            "usage: field-sig.py <json-file> <dotted.path>\n"
            "  e.g. field-sig.py Store/store.config.json "
            "listings.ko.description"
        )
    with open(sys.argv[1], encoding="utf-8") as fh:
        text = dig(json.load(fh), sys.argv[2])
    # 배열(keywords 등)을 넘기면 구분자 없이 이어 붙인 지문이 나와 콘솔과 영원히 어긋난다.
    # 그럴듯한 숫자를 돌려주는 검증 도구는 검증하지 않는 것보다 나쁘다.
    if not isinstance(text, str):
        sys.exit(
            f"'{sys.argv[2]}' 는 문자열이 아니라 {type(text).__name__} 다.\n"
            "  지문은 콘솔의 한 필드와 대조하는 용도다. 배열이면 콘솔이 쓰는 구분자로 먼저 합친다."
        )
    print(json.dumps({"head": head(text), **sig(text)}, ensure_ascii=False))
