import json
import sys
from pathlib import Path

import pytest
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import pack_textures as pt  # noqa: E402

MANIFEST_PATH = REPO_ROOT / "config" / "texture_manifest.json"


def _make_texture(path: Path, size=(16, 16), color=(255, 0, 0, 255)) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", size, color).save(path)
    return path


def _manifest_with(paths, block="STONE"):
    """Build a minimal manifest whose top face points at each path."""
    faces = {"top": paths[0] if paths else None, "side": None, "bottom": None}
    return {"version": 1, "blocks": {block: faces}}


def _multi_manifest(entries):
    """entries: list of (block_name, top_path)."""
    return {
        "version": 1,
        "blocks": {name: {"top": path, "side": None, "bottom": None} for name, path in entries},
    }


def test_deterministic_output(tmp_path):
    a = _make_texture(tmp_path / "alpha.png", (16, 16), (10, 20, 30, 255))
    b = _make_texture(tmp_path / "beta.png", (24, 12), (200, 10, 10, 255))
    manifest = _multi_manifest([("STONE", str(a)), ("DIRT", str(b))])

    img1, map1 = pt.generate_atlas(manifest)
    img2, map2 = pt.generate_atlas(manifest)

    assert img1.size == img2.size
    assert img1.tobytes() == img2.tobytes()
    assert json.dumps(map1["tiles"], sort_keys=True) == json.dumps(
        map2["tiles"], sort_keys=True
    )
    assert map1 == map2


def test_sources_sorted_for_determinism(tmp_path):
    z = _make_texture(tmp_path / "zeta.png")
    a = _make_texture(tmp_path / "alpha.png")
    manifest = _multi_manifest([("STONE", str(z)), ("DIRT", str(a))])
    assert pt.collect_sources(manifest) == sorted([str(z), str(a)])


def test_padding_inset_and_uv_rects(tmp_path):
    a = _make_texture(tmp_path / "a.png", (16, 16), (0, 255, 0, 255))
    b = _make_texture(tmp_path / "b.png", (32, 16), (0, 0, 255, 255))
    manifest = _multi_manifest([("STONE", str(a)), ("DIRT", str(b))])

    img, map_data = pt.generate_atlas(manifest, padding=2)
    assert map_data["atlas"]["padding"] == 2
    assert map_data["atlas"]["filter"] == "nearest"
    W = map_data["atlas"]["width"]
    H = map_data["atlas"]["height"]
    pad = 2

    padded_cells = []
    for path, tile in map_data["tiles"].items():
        x, y, w, h = tile["x"], tile["y"], tile["w"], tile["h"]

        # Inner rect is inset from the cell edge by exactly `padding`.
        assert x >= pad and y >= pad

        # UVs are normalized over final W/H and match the inner rect exactly.
        assert tile["u0"] == pytest.approx(x / W)
        assert tile["v0"] == pytest.approx(y / H)
        assert tile["u1"] == pytest.approx((x + w) / W)
        assert tile["v1"] == pytest.approx((y + h) / H)

        # UVs stay strictly inside the atlas (never touching the border).
        assert 0.0 < tile["u0"] < tile["u1"] < 1.0
        assert 0.0 < tile["v0"] < tile["v1"] < 1.0

        # Edge extrusion: the pad ring replicates the inner border pixels.
        for dx, dy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
            inner = img.getpixel((x + dx, y + dy))
            assert img.getpixel((x - 1, y + dy)) == inner
            assert img.getpixel((x + dx, y - 1)) == inner

        padded_cells.append((x - pad, y - pad, x + w + pad, y + h + pad))

    # Padded cells never overlap (each pair separated by at least 2*padding).
    for i in range(len(padded_cells)):
        for j in range(i + 1, len(padded_cells)):
            ax0, ay0, ax1, ay1 = padded_cells[i]
            bx0, by0, bx1, by1 = padded_cells[j]
            disjoint = ax1 <= bx0 or bx1 <= ax0 or ay1 <= by0 or by1 <= ay0
            assert disjoint


def test_missing_file_error_names_path(tmp_path):
    missing = tmp_path / "does_not_exist_xyz.png"
    manifest = _manifest_with([str(missing)])
    with pytest.raises(RuntimeError) as excinfo:
        pt.generate_atlas(manifest)
    assert "does_not_exist_xyz.png" in str(excinfo.value)


def test_overflow_error_with_tiny_max_size(tmp_path):
    a = _make_texture(tmp_path / "big.png", (64, 64))
    manifest = _manifest_with([str(a)])
    with pytest.raises(RuntimeError) as excinfo:
        pt.generate_atlas(manifest, max_size=8)
    message = str(excinfo.value)
    assert "big.png" in message
    assert "exceeds" in message.lower() or "overflow" in message.lower()


def test_real_manifest_all_non_null_paths_resolve(tmp_path):
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    img, map_data = pt.generate_atlas(manifest, base_dir=REPO_ROOT)

    references = [
        faces[face]
        for faces in manifest["blocks"].values()
        for face in ("top", "side", "bottom")
        if faces.get(face)
    ]
    # 15 block face references through M13 plus 3 each for the M14 OAK_LOG and
    # OAK_LEAVES blocks (AIR contributes none).
    assert len(references) == 21
    for rel in references:
        assert rel in map_data["tiles"]
    assert len(map_data["tiles"]) >= 6
    assert map_data["atlas"]["width"] <= 2048
    assert map_data["atlas"]["height"] <= 2048


def test_build_atlas_writes_only_to_given_paths(tmp_path):
    a = _make_texture(tmp_path / "a.png")
    manifest = _manifest_with([str(a)])
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    out_image = tmp_path / "out" / "gen_atlas.png"
    out_map = tmp_path / "out" / "atlas_map.json"

    result = pt.build_atlas(
        manifest_path=manifest_path,
        out_image=out_image,
        out_map=out_map,
        base_dir=REPO_ROOT,
    )

    assert out_image.is_file()
    assert out_map.is_file()
    written = json.loads(out_map.read_text(encoding="utf-8"))
    assert written == result
    assert written["version"] == 1
