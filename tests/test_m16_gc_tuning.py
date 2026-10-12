"""M16 stutter fix 1 - latency-first cyclic-GC policy.

These tests pin the *policy*, not a performance number: the collector must stay
enabled, the startup graph must be frozen exactly once, and post-freeze reference
cycles must still be reclaimed.

The module docstring of ``gc_tuning`` records the measurements that justify the
policy; before/after numbers live in the M16 diagnosis report.
"""

import gc
import sys
import weakref
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import gc_tuning  # noqa: E402


def test_apply_leaves_the_collector_enabled():
    """Freezing must not disable cyclic collection.

    Ursina/Panda3D object graphs contain reference cycles, so a disabled
    collector would leak entities and break the one-entity-per-loaded-chunk
    invariant.
    """
    gc_tuning.reset()
    try:
        gc_tuning.apply()
        assert gc.isenabled() is True
    finally:
        gc_tuning.reset()
        gc.enable()


def test_apply_does_not_change_the_collection_thresholds():
    """The refused lever: tuning thresholds provably does nothing here."""
    gc_tuning.reset()
    try:
        before = gc.get_threshold()
        gc_tuning.apply()
        assert gc.get_threshold() == before
    finally:
        gc_tuning.reset()


def test_apply_freezes_the_startup_graph_and_reports_it():
    gc_tuning.reset()
    assert gc.get_freeze_count() == 0
    assert gc_tuning.is_applied() is False
    try:
        assert gc_tuning.apply() is True
        assert gc.get_freeze_count() > 0
        assert gc_tuning.is_applied() is True
    finally:
        gc_tuning.reset()


def test_apply_is_one_shot():
    """A second call must not promote live gameplay objects to permanent."""
    gc_tuning.reset()
    try:
        assert gc_tuning.apply() is True
        frozen = gc.get_freeze_count()
        assert gc_tuning.apply() is False
        assert gc.get_freeze_count() == frozen
    finally:
        gc_tuning.reset()


def test_reference_cycles_created_after_apply_are_still_collected():
    """The freeze must not stop the collector reclaiming post-freeze garbage."""

    class Node:
        pass

    gc_tuning.reset()
    try:
        gc_tuning.apply()
        first = Node()
        second = Node()
        first.peer = second
        second.peer = first
        reference = weakref.ref(first)
        del first, second
        gc.collect()
        assert reference() is None
    finally:
        gc_tuning.reset()


def test_reset_restores_the_unfrozen_state():
    gc_tuning.apply()
    gc_tuning.reset()
    assert gc.get_freeze_count() == 0
    assert gc_tuning.is_applied() is False
    # And the policy can be applied again after a reset.
    try:
        assert gc_tuning.apply() is True
    finally:
        gc_tuning.reset()


if __name__ == "__main__":
    test_apply_leaves_the_collector_enabled()
    test_apply_does_not_change_the_collection_thresholds()
    test_apply_freezes_the_startup_graph_and_reports_it()
    test_apply_is_one_shot()
    test_reference_cycles_created_after_apply_are_still_collected()
    test_reset_restores_the_unfrozen_state()
    print("M16 GC tuning tests passed!")
