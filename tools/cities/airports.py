#!/usr/bin/env python3
"""Build Volant's airport time zone table from mwgg/Airports (MIT).

Writes Volant/Resources/airports.tsv.deflate: raw DEFLATE of UTF-8 lines with IATA code, IANA
zone and city, for every airport that has an IATA code. Also copies the dataset's MIT license to
Volant/Resources/Licenses/Airports-LICENSE.txt, which must ship with the data.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parent.parent.parent
BASE = "https://raw.githubusercontent.com/mwgg/Airports/master/"
OUTPUT = ROOT / "Volant" / "Resources" / "airports.tsv.deflate"
LICENSE = ROOT / "Volant" / "Resources" / "Licenses" / "Airports-LICENSE.txt"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--dir", type=Path, help="use a directory holding airports.json and LICENSE instead of fetching")
args = parser.parse_args()


def read(name):
    if args.dir:
        return (args.dir / name).read_bytes()
    return urllib.request.urlopen(BASE + name, timeout=60).read()


source = read("airports.json")
airports = json.loads(source)
rows = sorted({(a["iata"].upper(), a["tz"], a.get("city") or a["name"]) for a in airports.values()
               if a.get("iata") and len(a["iata"]) == 3 and a["iata"].isalpha() and a.get("tz")})
assert len({code for code, _, _ in rows}) == len(rows), "duplicate IATA codes"
payload = ("\n".join("\t".join(row) for row in rows) + "\n").encode("utf-8")
compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
OUTPUT.write_bytes(compressor.compress(payload) + compressor.flush())
LICENSE.write_bytes(read("LICENSE"))
print(f"{len(rows)} airports; {len(payload)} bytes -> {OUTPUT.stat().st_size} bytes")
print(f"source sha256 {hashlib.sha256(source).hexdigest()}")
