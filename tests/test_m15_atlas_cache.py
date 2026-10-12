"""M15 Task 3 - cached atlas map behaviour.

The atlas map is re-read from disk on every mesh rebuild today. These tests
pin the intended behaviour: a successful load is cached (stable identity), a
missing-asset result is *not* cached in a way that poisons a later successful
load, and ``reset_cache`` clears the atlas cache so tests stay isolated.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import texture_config as tc  # noqa: E402


def test_load_atlas_map_caches_identity():
    tc.reset_cache()
    first = tc.load_atlas_map()
    second = tc.load_atlas_map()
    assert first is not None
    assert "tiles" in first
    assert first is second


def test_load_atlas_map_returns_none_when_unavailable(monkeypatch):
    tc.reset_cache()
    monkeypatch.setattr(tc, "atlas_assets_available", lambda: False)
    try:
        assert tc.load_atlas_map() is None
    finally:
        tc.reset_cache()


def test_unavailable_result_does_not_poison_later_load(monkeypatch):
    tc.reset_cache()
    available = {"value": False}
    monkeypatch.setattr(tc, "atlas_assets_available", lambda: available["value"])

    assert tc.load_atlas_map() is None

    # Assets appear later; the earlier None must not have been cached.
    available["value"] = True
    loaded = tc.load_atlas_map()
    assert loaded is not None
    assert "tiles" in loaded


def test_reset_cache_clears_atlas_map():
    tc.reset_cache()
    first = tc.load_atlas_map()
    tc.reset_cache()
    second = tc.load_atlas_map()
    assert first == second
    # A cleared cache re-reads the file, so a fresh object is produced.
    assert first is not second


if __name__ == "__main__":
    test_load_atlas_map_caches_identity()
    test_load_atlas_map_returns_none_when_unavailable()
    test_unavailable_result_does_not_poison_later_load()
    test_reset_cache_clears_atlas_map()
    print("M15 atlas cache tests passed!")
