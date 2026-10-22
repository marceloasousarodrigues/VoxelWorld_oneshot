"""
Centralized chunk-streaming configuration for VoxelWorld (M16).

``config/world_config.json`` is the single source of truth for streaming
distance and the per-frame streaming work limits. This module loads that
document once and exposes validated values, so ``chunk_streaming`` and ``world``
never hard-code streaming settings.

It mirrors the M10 ``texture_config.py`` pattern: load once with ``lru_cache``,
degrade to defaults instead of failing, and expose ``reset_cache`` for test
isolation.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent

WORLD_CONFIG_PATH = REPO_ROOT / "config" / "world_config.json"

# Approved M16 defaults (spec §3). ``streaming_distance`` is the Chebyshev
# radius, in chunks, around the player's chunk that should be loaded;
# ``retention_distance`` is the larger radius outside which chunks unload.
# A load budget below 1 would stall streaming forever, so the minimum for both
# per-frame budgets is 1.
DEFAULTS = {
    "streaming_distance": 3,
    "retention_distance": 5,
    "max_chunk_loads_per_frame": 1,
    "max_chunk_unloads_per_frame": 4,
}

_MINIMUMS = {
    "streaming_distance": 0,
    "retention_distance": 0,
    "max_chunk_loads_per_frame": 1,
    "max_chunk_unloads_per_frame": 1,
}


def _read_document() -> dict:
    """Parse the config document, returning ``{}`` when it is unavailable."""
    try:
        with open(WORLD_CONFIG_PATH, encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, ValueError):
        return {}
    return document if isinstance(document, dict) else {}


def _coerce(key: str, raw) -> int:
    """Return ``raw`` when it is a valid value for ``key``, else the default.

    ``bool`` is rejected explicitly because it is an ``int`` subclass; a
    streaming setting should never be born from ``true``/``false``.
    """
    if isinstance(raw, bool) or not isinstance(raw, int):
        return DEFAULTS[key]
    if raw < _MINIMUMS[key]:
        return DEFAULTS[key]
    return raw


@lru_cache(maxsize=1)
def load_world_config() -> dict:
    """Load and validate the streaming configuration (cached once)."""
    document = _read_document()
    config = {
        key: _coerce(key, document.get(key, DEFAULTS[key])) for key in DEFAULTS
    }
    # Retention must never be smaller than streaming, or a chunk could be
    # unloaded while it is still desired.
    if config["retention_distance"] < config["streaming_distance"]:
        config["retention_distance"] = config["streaming_distance"]
    return config


def streaming_distance() -> int:
    """Chebyshev radius, in chunks, of the desired loaded set."""
    return load_world_config()["streaming_distance"]


def retention_distance() -> int:
    """Chebyshev radius, in chunks, outside which chunks unload."""
    return load_world_config()["retention_distance"]


def max_chunk_loads_per_frame() -> int:
    """At most this many chunks are loaded in one streamer update."""
    return load_world_config()["max_chunk_loads_per_frame"]


def max_chunk_unloads_per_frame() -> int:
    """At most this many chunks are unloaded in one streamer update."""
    return load_world_config()["max_chunk_unloads_per_frame"]


def reset_cache() -> None:
    """Clear the cached configuration (for test isolation)."""
    load_world_config.cache_clear()
