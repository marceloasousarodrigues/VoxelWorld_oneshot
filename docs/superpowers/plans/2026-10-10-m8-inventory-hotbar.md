# M8 — Inventory, Hotbar & Resource Collection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a basic inventory system, hotbar, and resource collection to enable inventory-bound block placement.

**Architecture:** A lightweight `Inventory` component manages `ItemStack` objects (block type + quantity) in a fixed slot structure. Breaking and placing are updated to interface with this `Inventory`. The inventory state is independent of `World` and `Chunk` data.

**Tech Stack:** Python, `numpy` (existing).

**Spec:** docs/superpowers/specs/2026-10-09-m8-inventory-design.yaml

## Global Constraints

- Inventory must support block types: GRASS, DIRT, STONE.
- Maximum stack size: 64.
- Total inventory capacity: 27 slots (9 hotbar + 18 inventory).
- Inventory toggle: 'E'. Hotbar selection: '1'–'9'.
- Preserves M1–M7 world interaction and chunk rendering.
- No new entity-per-voxel representation in inventory.

## Review Focus

1. **Inventory Full:** Breaking a block when inventory is full (all slots occupied or existing stack full) does NOT break the block. (Test: `test_inventory_full_rejects_break`)
2. **Placement Consumption:** Successful placement consumes 1 item. Failed/rejected placement (collision, invalid target) does NOT consume an item. (Test: `test_place_consumes_inventory_item`)
3. **Boundary Interaction:** Placing/Breaking boundary-adjacent blocks trigger `world.refresh()` for all loaded neighbor chunks. (Test: Existing `tests/test_place_block.py`)
4. **Invalid Place:** Trying to place a block not in the selected hotbar slot rejects placement. (Test: `test_place_requires_held_item`)
5. **Stack Merging:** Collecting multiple blocks of the same type merges correctly into stacks. (Test: `test_inventory_stacks_items`)

---

### Task 1: Inventory Data Model & Logic

**Files:**
- Create: `inventory.py`, `tests/test_inventory.py`

**Interfaces:**
- Consumes: BlockType
- Produces: Inventory class, ItemStack class(item, quantity), add_item(item, qty), remove_item(item, qty), can_add(item, qty)

- [ ] **Step 1: Write tests for stack limits, inventory full, and slot management**
- [ ] **Step 2: Implement `Inventory` and `ItemStack`**
- [ ] **Step 3: Run inventory tests**
- [ ] **Step 4: Commit**

### Task 2: Resource Collection

**Files:**
- Modify: `player.py`, `tests/test_player_collection.py`

**Interfaces:**
- Consumes: Inventory.can_add, Inventory.add_item
- Produces: Updated break_block (added resource collection)

- [ ] **Step 1: Write test for break_block adding to inventory**
- [ ] **Step 2: Update `VoxelPlayer` to use inventory in `break_block`**
- [ ] **Step 3: Run collection tests**
- [ ] **Step 4: Commit**

### Task 3: Hotbar UI & Selection Logic

**Files:**
- Create: `inventory_ui.py`
- Modify: `player.py`, `main.py`, `tests/test_hotbar.py`

**Interfaces:**
- Consumes: Player input ('1'-'9', 'E'), Inventory contents
- Produces: Hotbar slot selection index, visual inventory UI

- [ ] **Step 1: Write tests for hotbar selection**
- [ ] **Step 2: Implement hotbar selection logic in `VoxelPlayer`**
- [ ] **Step 3: Create inventory UI entity**
- [ ] **Step 4: Run UI/Hotbar tests**
- [ ] **Step 5: Commit**

### Task 4: Inventory-Aware Placement

**Files:**
- Modify: `player.py`, `tests/test_inventory_placement.py`

**Interfaces:**
- Consumes: Inventory contents, selected hotbar slot
- Produces: Updated place_block (conditional on item availability)

- [ ] **Step 1: Write test for place_block consuming from inventory**
- [ ] **Step 2: Update `VoxelPlayer.place_block` to check/consume items**
- [ ] **Step 3: Run integration tests**
- [ ] **Step 4: Commit**
