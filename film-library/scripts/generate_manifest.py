#!/usr/bin/env python3
"""Generate filters.json manifest from HaldCLUT files with brand-based metadata."""

import json
import re
from pathlib import Path

HALDCLUT_ROOT = Path(__file__).parent.parent / "haldclut" / "rawtherapee"

# Brand metadata: tags, avoid_tags, grain suggestion, notes
BRAND_META = {
    "Agfa": {
        "tags": ["punchy", "saturated", "vivid"],
        "avoid_tags": [],
        "grain": "medium",
        "notes": "Agfa 胶卷，色彩浓郁偏鲜艳",
    },
    "Fuji": {
        "tags": ["fuji", "natural-green"],
        "avoid_tags": [],
        "grain": "light",
        "notes": "富士胶卷，绿色表现好",
    },
    "Kodak": {
        "tags": ["kodak", "warm"],
        "avoid_tags": [],
        "grain": "light",
        "notes": "柯达胶卷，整体偏暖",
    },
    "Lomography": {
        "tags": ["lomo", "cross-process", "experimental", "vintage"],
        "avoid_tags": ["portrait-conservative"],
        "grain": "heavy",
        "notes": "Lomo 风格，色偏激进，适合实验性用途",
    },
    "Polaroid": {
        "tags": ["polaroid", "instant", "vintage", "retro"],
        "avoid_tags": [],
        "grain": "medium",
        "notes": "宝丽来即时胶片风格",
    },
    "CreativePack-1": {
        "tags": ["creative", "stylized"],
        "avoid_tags": [],
        "grain": "none",
        "notes": "创意风格预设，非模拟真实胶卷",
    },
    "Ilford": {
        "tags": ["ilford", "black-and-white", "classic-bw"],
        "avoid_tags": [],
        "grain": "medium",
        "notes": "Ilford 经典黑白胶卷",
    },
    "Rollei": {
        "tags": ["rollei", "black-and-white", "specialty-bw"],
        "avoid_tags": [],
        "grain": "medium",
        "notes": "Rollei 黑白胶卷，含红外特种片",
    },
}

# Film stock specific overrides
STOCK_META = {
    "Fuji 160C": {"tags": ["portrait", "natural-skin", "soft"], "grain": "fine", "notes": "富士 160C，人像首选，自然肤色"},
    "Fuji 400H": {"tags": ["portrait", "wedding", "versatile", "warm"], "grain": "fine", "notes": "富士 400H，婚礼人像经典，微暖"},
    "Fuji 800Z": {"tags": ["low-light", "indoor", "warm"], "grain": "medium", "notes": "富士 800Z，高感胶卷，适合弱光"},
    "Fuji Superia": {"tags": ["consumer", "punchy", "everyday"], "grain": "medium", "notes": "富士 Superia，日常消费级胶卷"},
    "Fuji Velvia": {"tags": ["landscape", "saturated", "vivid"], "avoid_tags": ["portrait", "skin"], "grain": "fine", "notes": "富士 Velvia，极高饱和度，风景片首选，不适合人像"},
    "Fuji Provia": {"tags": ["landscape", "saturated", "slide"], "grain": "fine", "notes": "富士 Provia，反转片，色彩准确饱和"},
    "Kodak Portra": {"tags": ["portrait", "skin", "subtle-warm", "wedding"], "grain": "fine", "notes": "柯达 Portra，人像之王，肤色优秀"},
    "Kodak Ektar": {"tags": ["landscape", "saturated", "vivid"], "grain": "fine", "notes": "柯达 Ektar，极高饱和度，风景片"},
    "Kodak Gold": {"tags": ["warm", "consumer", "everyday", "nostalgic"], "grain": "medium", "notes": "柯达 Gold，经典消费级暖调"},
    "Kodak KodakChrome": {"tags": ["classic", "saturated", "warm-red"], "grain": "fine", "notes": "柯达 KodakChrome，传奇反转片"},
}

# Variant strength suffix mapping
VARIANT_STRENGTH = {
    "1 ---": 0.25,
    "1 --": 0.3,
    "1 -": 0.4,
    "2 -": 0.45,
    "2": 0.55,
    "3 -": 0.5,
    "3": 0.6,
    "3 +": 0.65,
    "4": 0.7,
    "4 +": 0.75,
    "4 ++": 0.8,
    "5": 0.8,
    "5 +": 0.85,
    "5 ++": 0.9,
    "6 +++": 1.0,
    "6 ++": 0.95,
    "6 +": 0.9,
}

# Categorize into recipe groups
def categorize(tags: list[str], brand: str) -> str:
    tag_set = set(tags)
    if brand == "Lomography":
        return "experimental"
    if "portrait" in tag_set or "skin" in tag_set or "wedding" in tag_set:
        return "portrait"
    if "landscape" in tag_set or "saturated" in tag_set:
        return "street"  # street/landscape share a group for now
    if "low-light" in tag_set or "indoor" in tag_set:
        return "night"
    if "creative" in tag_set or "experimental" in tag_set:
        return "experimental"
    return "street"


def parse_variant(name: str, brand: str) -> tuple[str, float]:
    """Extract base stock name and recommended strength from variant suffix."""
    # Try matching known suffixes longest-first
    for suffix, strength in sorted(VARIANT_STRENGTH.items(), key=lambda x: -len(x[0])):
        if name.endswith(" " + suffix):
            base = name[: -(len(suffix) + 1)].strip()
            return base, strength
    return name, 0.55  # default mid-strength


def build_filter_entry(png_path: Path, brand: str, is_bw: bool) -> dict:
    name = png_path.stem
    base_stock, strength = parse_variant(name, brand)

    # Look up stock-specific metadata
    stock_meta = None
    for stock_key, meta in STOCK_META.items():
        if base_stock.startswith(stock_key):
            stock_meta = meta
            break

    brand_meta = BRAND_META.get(brand, BRAND_META.get("CreativePack-1", {}))

    tags = list(stock_meta.get("tags", brand_meta.get("tags", []))) if stock_meta else list(brand_meta.get("tags", []))
    avoid_tags = list(stock_meta.get("avoid_tags", brand_meta.get("avoid_tags", []))) if stock_meta else list(brand_meta.get("avoid_tags", []))
    grain = (stock_meta or brand_meta).get("grain", "light")
    notes = (stock_meta or brand_meta).get("notes", "")

    if is_bw:
        tags = ["black-and-white", "monochrome"] + [t for t in tags if t not in ("saturated", "vivid", "punchy")]

    # Check for warm/cold variant in name
    if "Cold" in name:
        tags.append("cool-tone")
    elif "Warm" in name:
        tags.append("warm-tone")

    # Build relative path from film-library root
    rel_path = str(png_path.relative_to(HALDCLUT_ROOT.parent.parent))

    filter_id = re.sub(r"[^a-zA-Z0-9]+", "-", name).strip("-").lower()

    return {
        "id": filter_id,
        "name": name,
        "type": "bw" if is_bw else "color",
        "file": rel_path,
        "family": brand.lower(),
        "base_stock": base_stock,
        "tags": sorted(set(tags)),
        "avoid_tags": sorted(set(avoid_tags)),
        "recommended_strength": strength,
        "grain": grain,
        "halation": "none",
        "source": "RawTherapee Film Simulation Collection",
        "category": categorize(tags, brand),
        "notes": notes,
    }


def main():
    filters = []

    # Color CLUTs
    for brand_dir in sorted(HALDCLUT_ROOT.iterdir()):
        if not brand_dir.is_dir() or brand_dir.name == "Black and White":
            continue
        brand = brand_dir.name
        for png in sorted(brand_dir.glob("*.png")):
            filters.append(build_filter_entry(png, brand, is_bw=False))

    # B&W CLUTs
    bw_root = HALDCLUT_ROOT / "Black and White"
    if bw_root.exists():
        for brand_dir in sorted(bw_root.iterdir()):
            if not brand_dir.is_dir():
                continue
            brand = brand_dir.name
            for png in sorted(brand_dir.glob("*.png")):
                filters.append(build_filter_entry(png, brand, is_bw=True))

    manifest = {
        "version": 1,
        "description": "Film simulation HaldCLUT filter catalogue",
        "total": len(filters),
        "filters": filters,
    }

    out_path = Path(__file__).parent.parent / "manifests" / "filters.json"
    out_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    print(f"Written {len(filters)} filters to {out_path}")

    # Stats
    categories = {}
    families = {}
    for f in filters:
        categories[f["category"]] = categories.get(f["category"], 0) + 1
        families[f["family"]] = families.get(f["family"], 0) + 1

    print("\nBy category:")
    for k, v in sorted(categories.items()):
        print(f"  {k}: {v}")
    print("\nBy family:")
    for k, v in sorted(families.items()):
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
