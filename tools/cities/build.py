#!/usr/bin/env python3
"""Build Volant's city time zone table from GeoNames cities15000 (CC BY 4.0).

Writes Volant/Resources/cities.tsv.deflate: raw DEFLATE of UTF-8 text whose first line lists
every IANA zone used, tab-separated, followed by one line per city:
name, ASCII name (empty when identical), country code, admin1 code, population, zone index.
Disambiguation happens in VolantCore's CityDirectory, so this keeps every city.
"""
import argparse
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile
import zlib

ROOT = Path(__file__).resolve().parent.parent.parent
SOURCE = "https://download.geonames.org/export/dump/cities15000.zip"
OUTPUT = ROOT / "Volant" / "Resources" / "cities.tsv.deflate"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--zip", type=Path, help="use a downloaded cities15000.zip instead of fetching it")
args = parser.parse_args()

archive = args.zip.read_bytes() if args.zip else urllib.request.urlopen(SOURCE, timeout=60).read()
with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
    text = bundle.read("cities15000.txt").decode("utf-8")

rows, zones = [], {}
for line in text.splitlines():
    fields = line.split("\t")
    if len(fields) < 18 or not fields[17]:
        continue
    name, ascii_name, country, admin1, population, zone = fields[1], fields[2], fields[8], fields[10], fields[14], fields[17]
    if any("\t" in value or "\n" in value for value in (name, ascii_name)):
        continue
    index = zones.setdefault(zone, len(zones))
    rows.append((name, "" if ascii_name == name else ascii_name, country, admin1, int(population or 0), index))

rows.sort(key=lambda row: (-row[4], row[0]))
lines = ["\t".join(zones)] + ["\t".join(str(value) for value in row) for row in rows]
payload = ("\n".join(lines) + "\n").encode("utf-8")
compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
OUTPUT.write_bytes(compressor.compress(payload) + compressor.flush())
print(f"{len(rows)} cities, {len(zones)} zones; {len(payload)} bytes -> {OUTPUT.stat().st_size} bytes")
print(f"source sha256 {hashlib.sha256(archive).hexdigest()}")
