"""
M9 Task 2 - automated texture-atlas generator for VoxelWorld.

This script reads the authoritative texture manifest
(``config/texture_manifest.json``), collects every unique non-null source PNG,
shelf-packs them into a single atlas with 2px edge-extruded padding and writes:

  * ``voxel_textures/gen_atlas.png``  - the packed atlas image.
  * ``voxel_textures/atlas_map.json`` - the UV / pixel mapping metadata.

Packing is fully deterministic: sources are collected and sorted by their
manifest path, a fixed shelf order is used, and the emitted JSON is sorted by
key.

Schema of ``atlas_map.json``::

    {
      "version": 1,
      "atlas": {"width": W, "height": H, "padding": 2, "filter": "nearest"},
      "tiles": {
        "<source-path>": {
          "x": px, "y": px, "w": px, "h": px,
          "u0": f, "v0": f, "u1": f, "v1": f
        }
      }
    }

``(x, y, w, h)`` is the INNER (unpadded) rectangle in atlas pixels.  The UVs
are normalized over the final atlas ``W``/``H`` and inset to that inner
rectangle (``u0 = x/W``, ``v0 = y/H``, ``u1 = (x+w)/W``, ``v1 = (y+h)/H``).

Usage (from the repository root)::

    python scripts/pack_textures.py
    python scripts/pack_textures.py --max-size 512
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent

DEFAULT_MANIFEST = REPO_ROOT / "config" / "texture_manifest.json"
DEFAULT_OUT_IMAGE = REPO_ROOT / "voxel_textures" / "gen_atlas.png"
DEFAULT_OUT_MAP = REPO_ROOT / "voxel_textures" / "atlas_map.json"
DEFAULT_MAX_SIZE = 2048
DEFAULT_PADDING = 2

FACES = ("top", "side", "bottom")


# ---------------------------------------------------------------------------
# Manifest handling
# ---------------------------------------------------------------------------

def load_manifest(path) -> dict:
    """Load and return the texture manifest JSON document."""
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def collect_sources(manifest: dict) -> list:
    """Return the unique non-null source paths, sorted for determinism."""
    seen = set()
    for faces in manifest.get("blocks", {}).values():
        for face in FACES:
            rel = faces.get(face)
            if rel:
                seen.add(rel)
    return sorted(seen)


def _resolve(path_str, base_dir) -> Path:
    """Resolve a manifest path; absolute paths are used verbatim."""
    candidate = Path(path_str)
    if candidate.is_absolute():
        return candidate
    return Path(base_dir) / candidate


def find_missing(sources, base_dir) -> list:
    """Return the subset of ``sources`` that do not exist on disk."""
    return [rel for rel in sources if not _resolve(rel, base_dir).is_file()]


# ---------------------------------------------------------------------------
# Packing
# ---------------------------------------------------------------------------

def _pack(sizes, max_size: int, padding: int):
    """Shelf-pack ``sizes`` deterministically; return placements + dimensions.

    ``sizes`` is an ordered iterable of ``(path, (width, height))``.  Returns
    ``(placements, required_width, required_height)`` where ``placements`` maps
    path -> inner ``(x, y, w, h)``.
    """
    placements = {}
    cursor_x = 0
    cursor_y = 0
    shelf_height = 0
    required_width = 0

    for path, (width, height) in sizes:
        cell_w = width + 2 * padding
        cell_h = height + 2 * padding
        if cursor_x != 0 and cursor_x + cell_w > max_size:
            cursor_y += shelf_height
            cursor_x = 0
            shelf_height = 0
        inner_x = cursor_x + padding
        inner_y = cursor_y + padding
        placements[path] = (inner_x, inner_y, width, height)
        cursor_x += cell_w
        shelf_height = max(shelf_height, cell_h)
        required_width = max(required_width, cursor_x)

    required_height = cursor_y + shelf_height
    return placements, required_width, required_height


def _check_overflow(placements, required_w, required_h, max_size, padding) -> None:
    if required_w <= max_size and required_h <= max_size:
        return
    offenders = sorted(
        path
        for path, (ix, iy, w, h) in placements.items()
        if ix + w + padding > max_size or iy + h + padding > max_size
    )
    raise RuntimeError(
        f"Atlas overflow: required {required_w}x{required_h} exceeds max "
        f"{max_size}x{max_size}; offending textures: {', '.join(offenders)}"
    )


def _extrude_padding(cell: Image.Image, width: int, height: int, padding: int) -> None:
    """Replicate the border pixels of the inner image into the pad ring."""
    if padding <= 0:
        return
    cell_w = width + 2 * padding
    # Left / right strips.
    left = cell.crop((padding, padding, padding + 1, padding + height))
    cell.paste(left.resize((padding, height), Image.NEAREST), (0, padding))
    right = cell.crop(
        (padding + width - 1, padding, padding + width, padding + height)
    )
    cell.paste(right.resize((padding, height), Image.NEAREST), (padding + width, padding))
    # Top / bottom strips (full width, so corners are replicated too).
    top = cell.crop((0, padding, cell_w, padding + 1))
    cell.paste(top.resize((cell_w, padding), Image.NEAREST), (0, 0))
    bottom = cell.crop((0, padding + height - 1, cell_w, padding + height))
    cell.paste(bottom.resize((cell_w, padding), Image.NEAREST), (0, padding + height))


# ---------------------------------------------------------------------------
# Atlas generation
# ---------------------------------------------------------------------------

def generate_atlas(
    manifest: dict,
    base_dir=REPO_ROOT,
    padding: int = DEFAULT_PADDING,
    max_size: int = DEFAULT_MAX_SIZE,
):
    """Generate the atlas image and mapping dict from a manifest document.

    Returns ``(image, map_dict)``.  Raises ``RuntimeError`` if any non-null
    source is missing or the result exceeds ``max_size`` in either dimension.
    """
    sources = collect_sources(manifest)

    missing = find_missing(sources, base_dir)
    if missing:
        raise RuntimeError(
            "texture_manifest.json references missing files: "
            + ", ".join(sorted(missing))
        )

    sizes = []
    for rel in sources:
        with Image.open(_resolve(rel, base_dir)) as image:
            sizes.append((rel, image.size))

    placements, required_w, required_h = _pack(sizes, max_size, padding)
    _check_overflow(placements, required_w, required_h, max_size, padding)

    atlas_w = max(required_w, 1)
    atlas_h = max(required_h, 1)
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))

    tiles = {}
    for rel in sources:
        inner_x, inner_y, width, height = placements[rel]
        with Image.open(_resolve(rel, base_dir)) as raw:
            source = raw.convert("RGBA")
        cell = Image.new("RGBA", (width + 2 * padding, height + 2 * padding), (0, 0, 0, 0))
        cell.paste(source, (padding, padding))
        _extrude_padding(cell, width, height, padding)
        atlas.paste(cell, (inner_x - padding, inner_y - padding))
        tiles[rel] = {
            "x": inner_x,
            "y": inner_y,
            "w": width,
            "h": height,
            "u0": inner_x / atlas_w,
            "v0": inner_y / atlas_h,
            "u1": (inner_x + width) / atlas_w,
            "v1": (inner_y + height) / atlas_h,
        }

    map_data = {
        "version": 1,
        "atlas": {
            "width": atlas_w,
            "height": atlas_h,
            "padding": padding,
            "filter": "nearest",
        },
        "tiles": tiles,
    }
    return atlas, map_data


def build_atlas(
    manifest_path=DEFAULT_MANIFEST,
    out_image=DEFAULT_OUT_IMAGE,
    out_map=DEFAULT_OUT_MAP,
    max_size: int = DEFAULT_MAX_SIZE,
    padding: int = DEFAULT_PADDING,
    base_dir=REPO_ROOT,
) -> dict:
    """Load the manifest, generate the atlas and write both output files."""
    manifest = load_manifest(manifest_path)
    image, map_data = generate_atlas(
        manifest, base_dir=base_dir, padding=padding, max_size=max_size
    )

    out_image = Path(out_image)
    out_image.parent.mkdir(parents=True, exist_ok=True)
    image.save(out_image)

    out_map = Path(out_map)
    out_map.parent.mkdir(parents=True, exist_ok=True)
    with open(out_map, "w", encoding="utf-8") as handle:
        json.dump(map_data, handle, indent=2, sort_keys=True)
        handle.write("\n")

    return map_data


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Texture manifest path (default config/texture_manifest.json).",
    )
    parser.add_argument(
        "--out-image",
        type=Path,
        default=DEFAULT_OUT_IMAGE,
        help="Output atlas PNG (default voxel_textures/gen_atlas.png).",
    )
    parser.add_argument(
        "--out-map",
        type=Path,
        default=DEFAULT_OUT_MAP,
        help="Output atlas map JSON (default voxel_textures/atlas_map.json).",
    )
    parser.add_argument(
        "--max-size",
        type=int,
        default=DEFAULT_MAX_SIZE,
        help="Maximum atlas dimension in pixels (default 2048).",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = _parse_args(argv)
    map_data = build_atlas(
        manifest_path=args.manifest,
        out_image=args.out_image,
        out_map=args.out_map,
        max_size=args.max_size,
    )
    atlas = map_data["atlas"]
    print(
        f"[pack_textures] wrote {Path(args.out_image).as_posix()} "
        f"({atlas['width']}x{atlas['height']}, padding={atlas['padding']}) "
        f"and {Path(args.out_map).as_posix()} ({len(map_data['tiles'])} tiles)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
