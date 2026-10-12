"""M15 Task 1 - unit tests for the profiling harness metric helpers.

These tests import ``scripts/profile_m15`` without starting an Ursina
application: every helper under test is pure and takes plain data, so the
metric computation can be verified independently of the renderer.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.profile_m15 import (  # noqa: E402
    BUDGET_16_67,
    BUDGET_33_33,
    FrameStats,
    attribute,
    chunk_counts,
    pending_work,
    percentile,
)


def test_percentile_matches_linear_interpolation():
    values = [1.0, 2.0, 3.0, 4.0]
    assert percentile(values, 0.5) == 2.5
    assert percentile(values, 0.0) == 1.0
    assert percentile(values, 1.0) == 4.0
    # position = (4 - 1) * 0.25 = 0.75 -> 1.0 + (2.0 - 1.0) * 0.75 = 1.75
    assert percentile(values, 0.25) == 1.75


def test_percentile_single_sample_and_empty():
    assert percentile([7.5], 0.5) == 7.5
    assert percentile([], 0.5) is None


def test_frame_stats_exposes_percentiles_and_over_budget_counts():
    samples = [1.0, 10.0, 20.0, 40.0]
    stats = FrameStats(samples)
    ordered = sorted(samples)
    assert stats.p50 == percentile(ordered, 0.5)
    assert stats.p95 == percentile(ordered, 0.95)
    assert stats.p99 == percentile(ordered, 0.99)
    assert stats.max == 40.0
    assert stats.over_16_67 == 2
    assert stats.over_33_33 == 1
    assert stats.over_16_67_pct == 50.0


def test_frame_stats_thresholds_are_literal():
    assert BUDGET_16_67 == 16.67
    assert BUDGET_33_33 == 33.33
    # Exactly at the budget does not count as over it.
    assert FrameStats([16.67]).over_16_67 == 0
    assert FrameStats([16.68]).over_16_67 == 1
    assert FrameStats([33.33]).over_33_33 == 0
    assert FrameStats([33.34]).over_33_33 == 1


def test_frame_stats_empty_is_safe():
    stats = FrameStats([])
    assert stats.p50 is None
    assert stats.max is None
    assert stats.over_16_67 == 0
    assert stats.over_16_67_pct == 0.0


def test_attribute_sums_to_at_most_frame_total():
    result = attribute(50.0, {"interaction": 5.0, "mesh": 30.0})
    assert result["interaction"] == 5.0
    assert result["mesh"] == 30.0
    assert result["other"] == 15.0
    assert sum(result.values()) == 50.0


def test_attribute_clamps_negative_other_to_zero():
    result = attribute(10.0, {"interaction": 8.0, "mesh": 10.0})
    assert result["other"] == 0.0
    assert sum(result.values()) == 10.0


def test_attribute_includes_zeroed_known_categories():
    result = attribute(4.0, {"interaction": 1.0})
    for key in ("reconcile", "mesh", "water", "chunk_gen"):
        assert key in result
        assert result[key] == 0.0


class _FakeChunk:
    def __init__(self, has_entity):
        self.entity = object() if has_entity else None


class _FakeWorld:
    def __init__(self):
        self.chunks = {}
        self.dirty_chunks = set()


class _FakeWater:
    def __init__(self):
        self.pending_seeds = {}
        self.active_job = None


def test_pending_work_reports_queues():
    world = _FakeWorld()
    water = _FakeWater()
    world.dirty_chunks = {(0, 0, 0), (1, 0, 0)}
    water.pending_seeds = {(1, 2, 3): None}
    assert pending_work(world, water) == {
        "dirty_chunks": 2,
        "pending_seeds": 1,
        "active_job": False,
    }
    water.active_job = object()
    assert pending_work(world, water)["active_job"] is True


def test_chunk_counts_reports_loaded_visible_active_and_null_unloaded():
    world = _FakeWorld()
    world.chunks = {
        (0, 0, 0): _FakeChunk(True),
        (1, 0, 0): _FakeChunk(False),
    }
    world.dirty_chunks = {(0, 0, 0)}
    counts = chunk_counts(world)
    assert counts == {
        "loaded": 2,
        "visible": 1,
        "active": 1,
        "unloaded": None,
    }


if __name__ == "__main__":
    test_percentile_matches_linear_interpolation()
    test_percentile_single_sample_and_empty()
    test_frame_stats_exposes_percentiles_and_over_budget_counts()
    test_frame_stats_thresholds_are_literal()
    test_frame_stats_empty_is_safe()
    test_attribute_sums_to_at_most_frame_total()
    test_attribute_clamps_negative_other_to_zero()
    test_attribute_includes_zeroed_known_categories()
    test_pending_work_reports_queues()
    test_chunk_counts_reports_loaded_visible_active_and_null_unloaded()
    print("M15 harness tests passed!")
