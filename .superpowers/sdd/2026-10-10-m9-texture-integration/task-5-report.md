# Task 5 Report — Transparency Refactor & Chunk Entity (M9)

## STATUS
DONE (tests green)

## Files modified / created
- Modified: `chunk_mesh.py`
- Modified: `chunk_entity.py`
- Modified: `chunk.py`
- Created: `tests/test_transparency_child_entity.py`

## Key implementation decisions
- Added `generate_chunk_mesh_split(...)` usage to produce opaque + transparent geometry lists.
- Kept `generate_chunk_mesh(...)` signature intact and implemented it as concatenation of opaque + transparent geometry.
- Preserved the “one combined mesh concept” by still generating one opaque mesh list for the parent entity and one transparent mesh list for a child entity.
- Preserved legacy renderer until validated: child and parent entities use `voxel_textures/gen_atlas.png` only when BOTH `voxel_textures/gen_atlas.png` and `voxel_textures/atlas_map.json` exist; otherwise use `voxel_textures/blocks.png`.
- Transparency wiring: transparent geometry is rendered by a child entity with `transparency=True` and `render_queue=1`.

## Test commands + results
- `python -m pytest tests/ -q --tb=no`
  - Output: `69 passed`
- `python -m pytest tests/test_chunk_refresh.py -q --tb=no`
  - Output: `3 passed`

## Notes / remaining gaps
- `voxel_textures/atlas_map.json` and `voxel_textures/gen_atlas.png` are NOT present in-repo at the time of this run, so the runtime renderer correctly falls back to `voxel_textures/blocks.png`.
- Visual verification (depth-sort correctness) not performed (no runtime/renderer inspection in this environment).
