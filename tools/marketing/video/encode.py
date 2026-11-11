#!/usr/bin/env python3
"""Encode the feature video frames that render.swift wrote into one MP4 per scene and the full video.

Frames are named volant-video-SS-NNNN-MS.png: scene SS (00 is the end card), frame NNNN, shown for
MS milliseconds. Each clip and the full video are 1080x1080 H.264 at 30 fps, yuv420p, with the moov
atom at the front (+faststart) and no audio track.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
FRAME = re.compile(r"volant-video-(\d\d)-(\d{4})-(\d+)\.png$")


def slug(title):
    """A file-name form of a scene title."""
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def encode(frames, output):
    """Encodes (path, milliseconds) frames into one MP4 through ffmpeg's concat demuxer."""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as listing:
        for path, milliseconds in frames:
            listing.write(f"file '{path}'\nduration {milliseconds / 1000:.3f}\n")
        # The concat demuxer drops the last entry's duration unless the file is listed again; the
        # output is then cut to the frames' total length.
        listing.write(f"file '{frames[-1][0]}'\n")
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing.name,
                    "-vf", "fps=30,format=yuv420p", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-tune", "stillimage",
                    "-profile:v", "high", "-movflags", "+faststart", "-an", "-t", f"{sum(ms for _, ms in frames) / 1000:.3f}", str(output)], check=True)
    Path(listing.name).unlink()


def main():
    """Groups the frames by scene, then writes each clip with its title card and the full video."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path, help="folder holding the volant-video-*.png frames")
    parser.add_argument("--output", type=Path, default=ROOT / "dist-video")
    args = parser.parse_args()
    scenes = json.loads((ROOT / "tools/marketing/video/scenes.json").read_text())["scenes"]
    titles = {scene["number"]: scene["title"] for scene in scenes}
    grouped = {}
    for path in sorted(args.frames.glob("volant-video-*.png")):
        match = FRAME.search(path.name)
        if match:
            grouped.setdefault(int(match[1]), []).append((int(match[2]), path, int(match[3])))
    if not grouped:
        raise SystemExit(f"No video frames in {args.frames}")
    clips = args.output / "clips"
    clips.mkdir(parents=True, exist_ok=True)
    everything = []
    for number in sorted(grouped, key=lambda n: (n == 0, n)):
        frames = [(path, ms) for _, path, ms in sorted(grouped[number])]
        name = "end-card" if number == 0 else f"{number:02d}-{slug(titles.get(number, 'scene'))}"
        encode(frames, clips / f"{name}.mp4")
        print(f"{clips / (name + '.mp4')}: {sum(ms for _, ms in frames) / 1000:.1f} s")
        everything += frames
    full = args.output / "volant-features.mp4"
    encode(everything, full)
    print(f"{full}: {sum(ms for _, ms in everything) / 1000:.1f} s, {full.stat().st_size / 1_000_000:.1f} MB")


if __name__ == "__main__":
    main()
