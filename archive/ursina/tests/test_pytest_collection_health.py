"""Regression check for repository-level pytest collection health.

pytest's doctest plugin collects files matching its implicit ``test*.txt`` glob,
so non-doctest artefacts in the repository root (such as the UTF-16
``tests_final_report.txt`` log) used to abort collection with a
``UnicodeDecodeError`` before a single test ran.

Both ``pytest`` and ``pytest tests`` must stay usable from the repository root,
and collection must not be repaired by dropping real tests. These checks use
``--collect-only`` so the nested run never executes this module again.
"""

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REPORT_ARTEFACT = REPO_ROOT / "tests_final_report.txt"

# The suite that existed when the configuration was introduced; collection must
# never fall below it, or the collection fix would be hiding tests.
MIN_EXPECTED_COLLECTED = 334


def _collect_only(*args):
    # stdin=DEVNULL: the outer pytest session redirects the inherited stdin
    # handle, and duplicating it would fail on Windows (WinError 6).
    return subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", "-q", *args],
        cwd=str(REPO_ROOT),
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        errors="replace",
    )


def _collected_node_ids(result):
    return [line.strip() for line in result.stdout.splitlines() if "::" in line]


def test_bare_pytest_collection_from_repo_root_succeeds():
    result = _collect_only()
    output = result.stdout + result.stderr

    assert result.returncode == 0, output
    assert "UnicodeDecodeError" not in output, output
    assert "error during collection" not in output, output

    collected = _collected_node_ids(result)
    assert len(collected) >= MIN_EXPECTED_COLLECTED, output
    if REPORT_ARTEFACT.exists():
        assert not any(REPORT_ARTEFACT.name in node_id for node_id in collected), output


def test_scoped_pytest_collection_from_repo_root_succeeds():
    result = _collect_only("tests")
    output = result.stdout + result.stderr

    assert result.returncode == 0, output
    assert "UnicodeDecodeError" not in output, output
    assert "error during collection" not in output, output

    collected = _collected_node_ids(result)
    assert len(collected) >= MIN_EXPECTED_COLLECTED, output
    assert all(node_id.startswith("tests/") or node_id.startswith("tests\\")
               for node_id in collected), output
