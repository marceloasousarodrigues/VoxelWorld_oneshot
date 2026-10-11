"""
Centralized texture configuration for VoxelWorld.

The per-face source PNG assignments live in ``config/texture_manifest.json``,
which is the single source of truth for texture paths. This module loads that
manifest once and exposes the resulting lookups alongside the generated atlas
paths and the legacy atlas path, so that ``block_data``, ``chunk_mesh`` and
``chunk_entity`` do not duplicate hardcoded paths.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent

MANIFEST_PATH = REPO_ROOT / "config" / "texture_manifest.json"
ATLAS_IMAGE_PATH = REPO_ROOT / "voxel_textures" / "gen_atlas.png"
ATLAS_MAP_PATH = REPO_ROOT / "voxel_textures" / "atlas_map.json"
LEGACY_ATLAS_PATH = REPO_ROOT / "voxel_textures" / "blocks.png"

# Relative (forward-slash) strings handed to Ursina, preserving the previous
# path strings used by the renderer.
TEXTURE_M9 = "voxel_textures/gen_atlas.png"
TEXTURE_LEGACY = "voxel_textures/blocks.png"

_FACES = ("top", "side", "bottom")


@lru_cache(maxsize=1)
def load_manifest() -> dict:
    """Load and cache the texture manifest.

    Returns an empty document when the manifest is missing or unreadable so
    callers degrade gracefully instead of failing at import time.
    """
    try:
        with open(MANIFEST_PATH, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def block_face_textures(block_name: str) -> dict:
    """Return the ``{top, side, bottom}`` source paths for a block name.

    ``block_name`` is the manifest key (e.g. ``"GRASS"``). Missing blocks or
    faces map to ``None``.
    """
    faces = load_manifest().get("blocks", {}).get(block_name, {})
    return {face: faces.get(face) for face in _FACES}


def atlas_assets_available() -> bool:
    """Return whether both generated atlas assets (image and map) exist."""
    return ATLAS_IMAGE_PATH.is_file() and ATLAS_MAP_PATH.is_file()


def load_atlas_map() -> dict | None:
    """Load the generated atlas map, or ``None`` when the atlas is unavailable."""
    if not atlas_assets_available():
        return None
    with open(ATLAS_MAP_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def reset_cache() -> None:
    """Clear the cached manifest (for test isolation)."""
    load_manifest.cache_clear()
