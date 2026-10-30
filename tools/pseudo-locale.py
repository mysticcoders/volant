#!/usr/bin/env python3
"""Compiles a pseudo-locale, en-XA, from Volant's String Catalogs into an app bundle's Resources, for
layout review in the native fixtures. See docs/localization.md.

Each string becomes accented look-alike letters, about 35% longer, inside brackets, such as
"Refresh" -> "[Ŕéƒŕéšĥ~~]": a clipped end loses its bracket, and text that stays plain English never
went through a catalog. Format specifiers, line breaks and URLs are kept, and plural variants keep
their categories. Launch a fixture with `-AppleLanguages "(en-XA)"`; add
`-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES` for a right-to-left layout.

  tools/pseudo-locale.py --output-directory <bundle>/Contents/Resources
"""
import argparse
import copy
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = ("Localizable.xcstrings", "Core.xcstrings")
LANGUAGE = "en-XA"
GROWTH = 0.35
LETTERS = dict(zip("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
                   "áƀçðéƒĝĥíĵķĺɱñóþǫŕšţúṽŵẋýžÁƁÇÐÉƑĜĤÍĴĶĹṀÑÓÞǪŔŠŢÚṼŴẊÝŽ"))
KEPT = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA%]|https?://\S+|\n")


def pseudo(text):
    """Accented, bracketed and padded text that keeps every specifier, URL and line break as it is."""
    parts, last, visible = [], 0, 0
    for match in KEPT.finditer(text):
        plain = text[last:match.start()]
        parts.append("".join(LETTERS.get(c, c) for c in plain))
        visible += len(plain)
        parts.append(match.group(0))
        last = match.end()
    plain = text[last:]
    parts.append("".join(LETTERS.get(c, c) for c in plain))
    visible += len(plain)
    padding = max(0, math.ceil(visible * GROWTH) - 2)
    return "[" + "".join(parts) + "~" * padding + "]"


def localize(node):
    """A copy of an English localization with every string unit made pseudo."""
    node = copy.deepcopy(node)
    stack = [node]
    while stack:
        item = stack.pop()
        if isinstance(item, dict):
            unit = item.get("stringUnit")
            if isinstance(unit, dict) and "value" in unit:
                unit["value"] = pseudo(unit["value"])
                unit["state"] = "translated"
            stack.extend(item.values())
        elif isinstance(item, list):
            stack.extend(item)
    return node


def catalog(source):
    """A catalog holding only the pseudo-locale for every translatable string in `source`."""
    strings = {}
    for key, entry in json.loads(source.read_text())["strings"].items():
        if not entry.get("shouldTranslate", True):
            continue
        english = entry.get("localizations", {}).get("en") or {"stringUnit": {"state": "translated", "value": key}}
        strings[key] = {"localizations": {LANGUAGE: localize(english)}}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        for name in CATALOGS:
            path = Path(scratch) / name
            path.write_text(json.dumps(catalog(ROOT / "Volant/Resources" / name), ensure_ascii=False))
            result = subprocess.run(["xcrun", "xcstringstool", "compile", str(path), "--output-directory", str(args.output_directory)],
                                    capture_output=True, text=True)
            if result.returncode:
                sys.exit(result.stderr or result.stdout)
    print(f"Compiled {LANGUAGE} into {args.output_directory}")


if __name__ == "__main__":
    main()
