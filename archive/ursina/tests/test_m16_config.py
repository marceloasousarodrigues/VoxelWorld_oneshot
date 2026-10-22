"""M16 Task 1 — centralized streaming configuration.

``world_config`` mirrors the M10 ``texture_config`` pattern: a single JSON
document read once, validated, with graceful defaults and a reset hook. These
tests exercise the loader directly without starting an Ursina application.
"""

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import world_config  # noqa: E402

DEFAULTS = {
    "streaming_distance": 3,
    "retention_distance": 5,
    "max_chunk_loads_per_frame": 1,
    "max_chunk_unloads_per_frame": 4,
}


def _point_at(monkeypatch, tmp_path, document):
    """Write ``document`` to a temp file and point world_config at it."""
    path = tmp_path / "world_config.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    monkeypatch.setattr(world_config, "WORLD_CONFIG_PATH", path)
    world_config.reset_cache()
    return path


def _current():
    return (
        world_config.streaming_distance(),
        world_config.retention_distance(),
        world_config.max_chunk_loads_per_frame(),
        world_config.max_chunk_unloads_per_frame(),
    )


def test_shipped_config_matches_approved_defaults():
    world_config.reset_cache()
    assert _current() == (
        DEFAULTS["streaming_distance"],
        DEFAULTS["retention_distance"],
        DEFAULTS["max_chunk_loads_per_frame"],
        DEFAULTS["max_chunk_unloads_per_frame"],
    )


def test_missing_values_fall_back_to_defaults(monkeypatch, tmp_path):
    _point_at(monkeypatch, tmp_path, {})
    assert _current() == (
        DEFAULTS["streaming_distance"],
        DEFAULTS["retention_distance"],
        DEFAULTS["max_chunk_loads_per_frame"],
        DEFAULTS["max_chunk_unloads_per_frame"],
    )


def test_values_are_loaded_from_json(monkeypatch, tmp_path):
    _point_at(
        monkeypatch,
        tmp_path,
        {
            "streaming_distance": 2,
            "retention_distance": 4,
            "max_chunk_loads_per_frame": 3,
            "max_chunk_unloads_per_frame": 7,
        },
    )
    assert _current() == (2, 4, 3, 7)


def test_invalid_values_fall_back_to_defaults(monkeypatch, tmp_path):
    _point_at(
        monkeypatch,
        tmp_path,
        {
            "streaming_distance": -1,
            "retention_distance": "many",
            "max_chunk_loads_per_frame": 0,
            "max_chunk_unloads_per_frame": None,
        },
    )
    # A load budget of 0 would stall streaming, so it is invalid too.
    assert _current() == (
        DEFAULTS["streaming_distance"],
        DEFAULTS["retention_distance"],
        DEFAULTS["max_chunk_loads_per_frame"],
        DEFAULTS["max_chunk_unloads_per_frame"],
    )


def test_retention_never_below_streaming(monkeypatch, tmp_path):
    _point_at(
        monkeypatch,
        tmp_path,
        {"streaming_distance": 6, "retention_distance": 2},
    )
    assert (
        world_config.streaming_distance()
        <= world_config.retention_distance()
    )


def test_unreadable_file_falls_back_to_defaults(monkeypatch, tmp_path):
    path = tmp_path / "missing.json"
    monkeypatch.setattr(world_config, "WORLD_CONFIG_PATH", path)
    world_config.reset_cache()
    assert _current() == (
        DEFAULTS["streaming_distance"],
        DEFAULTS["retention_distance"],
        DEFAULTS["max_chunk_loads_per_frame"],
        DEFAULTS["max_chunk_unloads_per_frame"],
    )


def test_reset_cache_reloads_changed_file(monkeypatch, tmp_path):
    path = _point_at(monkeypatch, tmp_path, {"streaming_distance": 1})
    assert world_config.streaming_distance() == 1

    path.write_text(json.dumps({"streaming_distance": 4}), encoding="utf-8")
    # Cached until reset.
    assert world_config.streaming_distance() == 1
    world_config.reset_cache()
    assert world_config.streaming_distance() == 4
