# M9 — Texture Pack Integration — Architectural Design

> Active milestone: M9. Architectural path.

## 1. Intent
Integrate a high-resolution Minecraft-style texture pack (32x32+) while maintaining the sharp pixel-art aesthetic. Upgrade the renderer from a hard-coded 3-face UV atlas to a dynamic, face-specific texture system that supports transparency and separate top/side/bottom face rendering.

## 2. Invariants
- **Performance:** One logical combined Chunk management per Chunk. Post-integration performance metrics (FPS, memory, refresh duration) must be equivalent to pre-integration baseline (measured via `scripts/measure_baseline.py`, 30s benchmark).
- **Data Truth:** The logical block data and the atlas mapping remain synchronized.
- **Visual:** Pixel-perfect sharpness using `texture_filter='nearest'`.
- **Transparency Architecture Exception:** The "One Entity per Chunk" invariant is modified to "One Entity *Container* per Chunk". To ensure correct depth-sorting and keep opaque geometry depth-writing intact, transparent faces are split into a separate child `Entity` (render_queue 1), while opaque faces remain in the primary chunk `Entity` (render_queue 0). This preserves the logical parent-child tree while solving the transparency-induced depth-write issues.

## 3. Architecture
- **Automated Atlas Generator (`scripts/pack_textures.py`):** Reads textures (from `config/texture_manifest.json`), packs them into `gen_atlas.png` (max 2048x2048), writing `atlas_map.json`. Uses 2px edge-extruded padding.
- **Atlas Metadata:** `atlas_map.json` includes atlas dimensions and UV coordinates (normalized `(u0, v0, u1, v1)`).
- **Face-Specific Mapping:** `block_data.py` defines `{top, side, bottom}` texture references per `BlockType` and an `is_transparent` flag.
- **Dynamic Renderer:** `chunk_mesh.py` refactored to look up UVs from `atlas_map.json` and separate opaque/transparent geometry during mesh regeneration.
- **Transparency Handling:** Transparent block faces, if present, are added to a child `Entity` instance, allowing transparent rendering (`Entity.transparency=True`, `render_queue=1`) without breaking opaque depth-writing on the main chunk `Entity`.
- **Compatibility:** Legacy `blocks.png` path is preserved; `World` configuration selects the legacy or M9 rendering path.

## 4. Visual Verification Criteria
- **UV Precision:** Block textures are displayed correctly mapped on top, side, and bottom.
- **Transparency Sorting:** Transparent plants render correctly (depth tested) against background chunks, using standard `render_queue` sorting.
- **Texture Integrity:** Nearest-neighbor filtering ensures pixel sharpness (no blur); 2px padding ensures no bleeding.
- **UI:** Inventory and hotbar icons load from `voxel_textures/blocks/` (fallback path).

## Required assets
- `voxel_textures/blocks/water.png` is required for `BlockType.WATER` to render; `chunk_mesh.py` routes WATER faces through the transparent child entity path.
