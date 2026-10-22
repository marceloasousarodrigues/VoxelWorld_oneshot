"""Focused tests for the M16 harnesses' recorded environment metadata.

Both harnesses write the engine and library versions into their ``meta`` block.
Those helpers must read package metadata instead of ``module.__version__``:
Ursina exposes no ``__version__``, so an attribute lookup recorded
``unknown``/``unavailable`` while ursina 8.3.0 was installed and in use.

The harness modules are imported here without starting an Ursina application,
and the helper never imports the package it reports on.
"""

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts import measure_m16_streaming, profile_m16_stutter  # noqa: E402

REPORTED = ("ursina", "panda3d", "numpy")

# (harness module, the marker it records when a distribution is unknown)
HARNESSES = [
    pytest.param(measure_m16_streaming, "unknown", id="measure_m16_streaming"),
    pytest.param(profile_m16_stutter, "unavailable", id="profile_m16_stutter"),
]


@pytest.mark.parametrize("harness,fallback", HARNESSES)
def test_recorded_versions_come_from_installed_package_metadata(harness, fallback):
    from importlib.metadata import version

    for distribution in REPORTED:
        assert harness._version(distribution) == version(distribution)
        assert harness._version(distribution) != fallback


@pytest.mark.parametrize("harness,fallback", HARNESSES)
def test_uninstalled_distribution_reports_the_fallback_not_an_exception(harness, fallback):
    assert harness._version("voxelworld-distribution-that-is-not-installed") == fallback
