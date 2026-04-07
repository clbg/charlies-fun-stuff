#!/usr/bin/env python3
"""Film filter execution tool: apply HaldCLUT filters with ImageMagick.

AI analysis and recommendation handled by the calling agent (Claude Code, etc.).
This script only does deterministic image processing.

Usage:
    # Apply a specific filter
    ./film_filter.py apply <input> <filter_id> [-o output] [-s strength] [-g grain]

    # Generate previews for multiple filters
    ./film_filter.py preview <input> <filter_id> [<filter_id>...] [-o output_dir]

    # List available filters (optionally filtered)
    ./film_filter.py list [--family fuji] [--category portrait] [--type color]

    # Show filter details
    ./film_filter.py info <filter_id>

Examples:
    ./film_filter.py apply photo.jpg fuji-160c-2 -s 0.6 -g light
    ./film_filter.py preview photo.jpg fuji-160c-2 kodak-portra-160-2 polaroid-669-3
    ./film_filter.py list --family fuji --type color
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

FILM_LIBRARY = Path(__file__).parent
MANIFEST_PATH = FILM_LIBRARY / "manifests" / "filters.json"

GRAIN_LEVELS = {"fine": 0.15, "light": 0.25, "medium": 0.4, "heavy": 0.6}


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text())


def find_filter(manifest: dict, filter_id: str) -> dict | None:
    for f in manifest["filters"]:
        if f["id"] == filter_id:
            return f
    return None


def resolve_clut_path(manifest: dict, filter_id: str) -> Path | None:
    f = find_filter(manifest, filter_id)
    if not f:
        return None
    return FILM_LIBRARY / f["file"]


def apply_lut(input_path: Path, clut_path: Path, output_path: Path, strength: float, grain: str) -> bool:
    """Apply HaldCLUT with ImageMagick, blend at given strength, optionally add grain."""
    strength_pct = int(strength * 100)
    cmd = [
        "magick", str(input_path),
        "(", "+clone", str(clut_path), "-hald-clut", ")",
        "-define", f"compose:args={strength_pct}",
        "-compose", "blend",
        "-composite",
    ]
    if grain in GRAIN_LEVELS:
        cmd.extend(["-attenuate", str(GRAIN_LEVELS[grain]), "+noise", "Gaussian"])
    cmd.append(str(output_path))

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: {result.stderr.strip()}", file=sys.stderr)
        return False
    return True


def make_preview(input_path: Path, clut_path: Path, output_path: Path, strength: float, grain: str) -> bool:
    """Generate a low-res (800px) preview."""
    strength_pct = int(strength * 100)
    cmd = [
        "magick", str(input_path),
        "-resize", "800x800>",
        "(", "+clone", str(clut_path), "-hald-clut", ")",
        "-define", f"compose:args={strength_pct}",
        "-compose", "blend",
        "-composite",
    ]
    if grain in GRAIN_LEVELS:
        cmd.extend(["-attenuate", str(GRAIN_LEVELS[grain]), "+noise", "Gaussian"])
    cmd.extend(["-quality", "85", str(output_path)])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: {result.stderr.strip()}", file=sys.stderr)
        return False
    return True


def cmd_apply(args, manifest):
    clut = resolve_clut_path(manifest, args.filter_id)
    if not clut or not clut.exists():
        print(f"Filter not found: {args.filter_id}", file=sys.stderr)
        sys.exit(1)

    inp = Path(args.input)
    if args.output:
        out = Path(args.output)
    else:
        out = inp.parent / f"{inp.stem}_{args.filter_id}{inp.suffix}"

    out.parent.mkdir(parents=True, exist_ok=True)
    strength = args.strength if args.strength is not None else find_filter(manifest, args.filter_id)["recommended_strength"]
    grain = args.grain or "none"

    if apply_lut(inp, clut, out, strength, grain):
        size_kb = out.stat().st_size / 1024
        print(f"{out} ({size_kb:.0f}KB)")


def cmd_preview(args, manifest):
    inp = Path(args.input)
    output_dir = Path(args.output_dir) if args.output_dir else inp.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    for fid in args.filter_ids:
        clut = resolve_clut_path(manifest, fid)
        if not clut or not clut.exists():
            print(f"SKIP: {fid} (not found)", file=sys.stderr)
            continue

        f = find_filter(manifest, fid)
        strength = args.strength if args.strength is not None else f["recommended_strength"]
        grain = args.grain or "none"
        out = output_dir / f"{inp.stem}_preview_{fid}.jpg"

        if make_preview(inp, clut, out, strength, grain):
            size_kb = out.stat().st_size / 1024
            print(f"{out} ({size_kb:.0f}KB)")


def cmd_list(args, manifest):
    filters = manifest["filters"]
    if args.family:
        filters = [f for f in filters if f["family"] == args.family]
    if args.category:
        filters = [f for f in filters if f["category"] == args.category]
    if args.type:
        filters = [f for f in filters if f["type"] == args.type]
    if args.tag:
        filters = [f for f in filters if args.tag in f["tags"]]

    if args.json:
        print(json.dumps(filters, ensure_ascii=False, indent=2))
    else:
        for f in filters:
            tags = ", ".join(f["tags"][:5])
            print(f"{f['id']:40s} {f['family']:15s} {f['type']:5s} {f['category']:12s} [{tags}]")
        print(f"\n{len(filters)} filters")


def cmd_info(args, manifest):
    f = find_filter(manifest, args.filter_id)
    if not f:
        print(f"Not found: {args.filter_id}", file=sys.stderr)
        sys.exit(1)
    print(json.dumps(f, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description="Film filter execution tool")
    sub = parser.add_subparsers(dest="command", required=True)

    # apply
    p_apply = sub.add_parser("apply", help="Apply a filter to an image")
    p_apply.add_argument("input", help="Input image path")
    p_apply.add_argument("filter_id", help="Filter ID from manifest")
    p_apply.add_argument("-o", "--output", help="Output path (default: input_filterid.ext)")
    p_apply.add_argument("-s", "--strength", type=float, help="Blend strength 0-1 (default: from manifest)")
    p_apply.add_argument("-g", "--grain", choices=list(GRAIN_LEVELS.keys()), help="Grain level")

    # preview
    p_preview = sub.add_parser("preview", help="Generate low-res previews")
    p_preview.add_argument("input", help="Input image path")
    p_preview.add_argument("filter_ids", nargs="+", help="Filter IDs to preview")
    p_preview.add_argument("-o", "--output-dir", help="Output directory")
    p_preview.add_argument("-s", "--strength", type=float, help="Override strength")
    p_preview.add_argument("-g", "--grain", choices=list(GRAIN_LEVELS.keys()), help="Grain level")

    # list
    p_list = sub.add_parser("list", help="List available filters")
    p_list.add_argument("--family", help="Filter by family (fuji, kodak, ...)")
    p_list.add_argument("--category", help="Filter by category (portrait, street, night, experimental)")
    p_list.add_argument("--type", help="Filter by type (color, bw)")
    p_list.add_argument("--tag", help="Filter by tag")
    p_list.add_argument("--json", action="store_true", help="Output as JSON")

    # info
    p_info = sub.add_parser("info", help="Show filter details")
    p_info.add_argument("filter_id", help="Filter ID")

    args = parser.parse_args()
    manifest = load_manifest()

    {"apply": cmd_apply, "preview": cmd_preview, "list": cmd_list, "info": cmd_info}[args.command](args, manifest)


if __name__ == "__main__":
    main()
