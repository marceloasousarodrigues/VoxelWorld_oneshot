# M9 — Texture Pack Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate a Minecraft-style texture pack with face-aware mappings, transparency, and automated atlas generation using a chunk-container architecture.

**Architecture:** Automated generator creates `gen_atlas.png` + `atlas_map.json`. Renderer performs dynamic UV lookup, splitting meshes by transparency into two entities/sub-meshes under one container Entity per chunk.

**Spec:** docs/superpowers/specs/2026-10-10-m9-texture-integration-design.md

## Global Constraints

- **One Container Entity Per Chunk:** Combined logical mesh, split by functionality, but anchored to one Chunk parent Entity.
- **Dynamic UVs:** Dynamic lookup from `atlas_map.json`.
- **Texture Bleeding:** Min 2px padding, UVs clamped to inner region.
- **Max Atlas Size:** 2048x2048. If exceeded, generator raises `RuntimeError`.
- **Transparency:** `Entity.transparency=True` for child entity with transparent faces; `render_queue=1`.
- **No Refactoring:** Existing M1–M8 functionality MUST remain stable.
- **Regression:** Full 54-test baseline suite + new tests MUST pass after *every* task.
- **Performance:** Measured pre-integration, verified post-integration.

## Review Focus

1. **Performance Baseline:** Measurements captured *before* (Task 1) and verified *after* (Task 6).
2. **UV Accuracy:** `vertices` + faces map correctly per face-type. (Test: `test_mesh_face_uv_mapping`)
3. **Transparency Handling:** Transparent faces sort correctly over opacity. (Test: `test_rendering_transparency_sort`)
4. **Integration Checks:** All existing tests (54 baseline) + new tests MUST pass.
5. **Runtime Integrity:** Visually verify texture stability, face-specific textures, chunk boundaries, and transparency sorting.

---

### Task 1: Performance Baseline & Asset Audit

**Files:** Create: `scripts/measure_baseline.py`, `config/baseline_metrics.json (placeholder)`, `config/texture_manifest.json`

- [ ] **Step 1: Implement `measure_baseline.py` (measure 30s benchmark: FPS, refresh time, texture memory)**
- [ ] **Step 2: Collect baseline metrics, save to `config/baseline_metrics.json`**
- [ ] **Step 3: Audit `voxel_textures/blocks/` and create `config/texture_manifest.json`**
- [ ] **Step 4: Commit**

### Task 2: Automated Atlas Generator (with padding)

**Files:** Create: `scripts/pack_textures.py`

- [ ] **Step 1: Implement `pack_textures.py` (2px padding, max 2048x limit, `RuntimeError` on overflow)**
- [ ] **Step 2: Add validation tests for mapping consistency, padding, and overflow**
- [ ] **Step 3: Commit**

### Task 3: Block Data Face Refactor

**Files:** Modify: `block_data.py`

- [ ] **Step 1: Refactor `BLOCK_PROPERTIES` to include {top, side, bottom} mapping and `is_transparent` flag**
- [ ] **Step 2: Commit**

### Task 4: Mesh Generation Refactor

**Files:** Modify: `chunk_mesh.py`, `tests/test_chunk_mesh.py`

- [ ] **Step 1: Implement dynamic UV face-aware mapping in `chunk_mesh.py`**
- [ ] **Step 2: Add mesh-generation tests to verify boundary/face mapping**
- [ ] **Step 3: Commit**

### Task 5: Transparency Refactor & Chunk Entity

**Files:** Modify: `chunk_entity.py`

- [ ] **Step 1: Implement splitting of transparent geometry into a child `Entity` (render_queue=1)**
- [ ] **Step 2: Commit**

### Task 6: UI, Integration & Performance Verification

**Files:** Modify: `inventory_ui.py`

- [ ] **Step 1: Implement `InventoryUI` to load individual file textures (fallback to `blocks/`)**
- [ ] **Step 2: Perform post-integration performance check (Task 1 metrics) vs `config/baseline_metrics.json`**
- [ ] **Step 3: Perform final runtime visual verification (transparency, mapping stability, chunk boundaries)**
- [ ] **Step 4: Commit**
