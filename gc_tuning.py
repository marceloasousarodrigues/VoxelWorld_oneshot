"""
Latency-first cyclic-GC policy for VoxelWorld (M16 stutter investigation).

Measured problem
----------------
The CPython cyclic collector's occasional full (generation-2) pass costs 60-105 ms.
Because it fires from inside whatever operation happens to be running, it stacks on
top of a chunk-load frame and produces a 78-136 ms frame roughly once every few
thousand frames. It is the single worst stall in the game, and it is intermittent,
which makes it easy to mistake for random hitching.

What actually controls it (each measured, see the M16 diagnosis report)
-----------------------------------------------------------------------
* ``gc.set_threshold``'s third value has **no effect** on when a full collection
  runs on this Python build; the trigger is the collector's long-lived-growth
  heuristic. Raising it from 10 to 100000 changed the observed full-collection
  count from 1 to 1.
* Driving full collections explicitly on a fixed cadence is **worse**: an explicit
  ``gc.collect(2)`` measured 48-114 ms per call, against a 15-19 ms automatic
  collection once the startup graph is frozen.
* ``gc.freeze()`` is the lever that works. Moving the startup object graph (the
  world, its generated chunks, their entities and the whole Panda3D graph) into the
  permanent generation removes it from the oldest generation's candidate set, so
  every full collection traces far less. Measured on the real frame loop: worst
  full-collection pause 85-113 ms -> 15-56 ms, worst frame 113.1 -> 88.6 ms and
  95.1 -> 82.4 ms.

The trade-off is deliberate and honest: full collections become *more frequent*
(the growth heuristic's denominator shrinks) while each one is several times
cheaper. The tail improves sharply; p99 is essentially unchanged.

The collector is never disabled. Ursina/Panda3D object graphs contain reference
cycles, so disabling it would leak entities and break the one-entity-per-loaded-chunk
invariant.
"""

from __future__ import annotations

import gc

# Module state, not a config value: ``apply`` is a one-shot startup policy.
_applied = False


def apply() -> bool:
    """Freeze the startup object graph into the permanent generation.

    Call once, from the entry point, after the initial world and its rendered
    entities exist and before the frame loop starts. Everything created later
    stays collectable.

    Returns:
        True when this call performed the freeze, False when it was already
        applied (the policy is one-shot; a second call is a no-op so a later
        freeze cannot silently promote live gameplay objects to permanent).
    """
    global _applied
    if _applied:
        return False
    gc.freeze()
    _applied = True
    return True


def is_applied() -> bool:
    """Return True once ``apply`` has frozen the startup graph."""
    return _applied


def reset() -> None:
    """Undo the policy (unfreeze and allow ``apply`` to run again).

    For test isolation and for tooling that builds several worlds in one process.
    """
    global _applied
    gc.unfreeze()
    _applied = False
