#!/usr/bin/env python3
"""Keeps Volant's String Catalogs in step with the source. See docs/localization.md.

Localizable.xcstrings holds the app's strings, from the .stringsdata files the compiler writes for the
Volant target when SWIFT_EMIT_LOC_STRINGS is on, so interpolations carry their real format
specifiers. Run it after a Debug build into build/ (Scripts/test.sh does). Core.xcstrings holds
VolantCore's `table: "Core"` strings; the package target emits none, so they come from
xcstringstool's lightweight extraction, which is why Core strings must not interpolate.
InfoPlist.xcstrings must hold exactly the permission prompts in project.yml, with the same English.

  tools/strings.py           update the catalogs
  tools/strings.py --check   fail on strings the catalogs lack or describe differently, on prompts that
                             differ from project.yml, and on strings without Spanish. Unused strings are
                             marked stale only by a full sync, since an older SDK compiles less code.
"""
import argparse
import glob
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Volant/Resources"
CATALOGS = ("Localizable.xcstrings", "Core.xcstrings")
# Languages besides English that ship; every string in use needs a value in each.
SHIPPED_LANGUAGES = ("es", "de", "fr", "it", "ja", "zh-Hans", "pt-BR", "ko", "nl", "pl", "ru", "uk", "tr")


def app_stringsdata(build_dir):
    """The compiler's strings for the app target's own sources, one architecture's worth."""
    pattern = str(build_dir / "Build/Intermediates.noindex/Volant.build/Debug/Volant.build/Objects-normal/*/*.stringsdata")
    by_arch = {}
    for path in glob.glob(pattern):
        by_arch.setdefault(Path(path).parent.name, []).append(path)
    if not by_arch:
        sys.exit(f"No app .stringsdata under {build_dir}. Build Debug into it first (Scripts/build.sh or Scripts/test.sh).")
    return sorted(by_arch[sorted(by_arch)[0]])


def core_stringsdata(out):
    """VolantCore's Core-table strings, by lightweight extraction from its sources."""
    sources = sorted(str(p) for p in (ROOT / "Core/Sources").rglob("*.swift"))
    subprocess.run(["xcrun", "xcstringstool", "extract", "--modern-localizable-strings", "--table", "Core",
                    "--avoid-arg-placeholder", "--omit-empty-stringsdata", "-o", str(out)] + sources,
                   check=True, capture_output=True)
    return sorted(str(p) for p in out.glob("*.stringsdata"))


def sync(catalog_dir, build_dir, mark_stale=True):
    """Merges the current source strings into the catalogs in `catalog_dir`. Without `mark_stale`, strings
    this build didn't compile are left alone: code behind a newer SDK, such as macOS 26 dictation and
    Apple Intelligence, isn't compiled by older Xcode on CI, and its strings are still in use."""
    with tempfile.TemporaryDirectory() as scratch:
        data = app_stringsdata(build_dir) + core_stringsdata(Path(scratch))
        result = subprocess.run(["xcrun", "xcstringstool", "sync"] + [str(catalog_dir / c) for c in CATALOGS] + ["--stringsdata"] + data
                                + ([] if mark_stale else ["--skip-marking-strings-stale"]), capture_output=True, text=True)
        if result.returncode:
            sys.exit(result.stderr or result.stdout)


def prompt_problems():
    """Differences between project.yml's permission prompts and InfoPlist.xcstrings."""
    text = (ROOT / "project.yml").read_text()
    prompts = {m.group(1): m.group(2).replace('\\"', '"')
               for m in re.finditer(r'^\s+(NS\w+UsageDescription): "((?:[^"\\]|\\.)*)"', text, re.M)}
    catalog = json.loads((RESOURCES / "InfoPlist.xcstrings").read_text())["strings"]
    english = {k: v.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value") for k, v in catalog.items()}
    problems = [f"InfoPlist.xcstrings lacks {k}" for k in prompts if k not in english]
    problems += [f"InfoPlist.xcstrings has {k}, which project.yml doesn't" for k in english if k not in prompts]
    problems += [f"{k} differs between project.yml and InfoPlist.xcstrings" for k in prompts if k in english and english[k] != prompts[k]]
    return problems


def has_value(localization):
    """Whether a catalog localization carries text, directly or in every plural or device variant."""
    if localization.get("stringUnit", {}).get("value") is not None:
        return True
    variations = localization.get("variations", {})
    return bool(variations) and all(has_value(v) for kind in variations.values() for v in kind.values())


def missing_translations(catalog_dir):
    """Strings in use that lack a value in a shipped language, by catalog and language."""
    problems = []
    for name in CATALOGS + ("InfoPlist.xcstrings",):
        strings = json.loads((catalog_dir / name).read_text())["strings"]
        for language in SHIPPED_LANGUAGES:
            missing = sorted(key for key, entry in strings.items()
                             if entry.get("shouldTranslate", True) and entry.get("extractionState") != "stale"
                             and not has_value(entry.get("localizations", {}).get(language, {})))
            if missing:
                problems.append(f"{name}: {len(missing)} strings have no {language} text, e.g. {missing[:3]}")
    return problems


def changes(before, after):
    """Keys added, made stale or otherwise changed by a sync, for the check's message."""
    old, new = before["strings"], after["strings"]
    added = sorted(set(new) - set(old))
    stale = sorted(k for k, v in new.items() if v.get("extractionState") == "stale" and old.get(k, {}).get("extractionState") != "stale")
    changed = sorted(k for k in set(old) & set(new) if old[k] != new[k] and k not in stale)
    return added, stale, changed


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="report out-of-date catalogs without changing them")
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build")
    args = parser.parse_args()
    problems = prompt_problems() + missing_translations(RESOURCES)
    if not args.check:
        sync(RESOURCES, args.build_dir)
        print("Updated " + " and ".join(CATALOGS))
    else:
        with tempfile.TemporaryDirectory() as scratch:
            copy = Path(scratch)
            for catalog in CATALOGS:
                shutil.copy(RESOURCES / catalog, copy / catalog)
            sync(copy, args.build_dir, mark_stale=False)
            for catalog in CATALOGS:
                added, _, changed = changes(json.loads((RESOURCES / catalog).read_text()), json.loads((copy / catalog).read_text()))
                for label, keys in (("new", added), ("changed", changed)):
                    if keys:
                        problems.append(f"{catalog}: {len(keys)} {label}, e.g. {keys[:3]}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        if args.check:
            sys.exit("Strings are out of date. Run tools/strings.py after a Debug build, review the catalogs, and commit them.")
        sys.exit(1)
    if args.check:
        print("PASS: string catalogs and permission prompts match the source")


if __name__ == "__main__":
    main()
