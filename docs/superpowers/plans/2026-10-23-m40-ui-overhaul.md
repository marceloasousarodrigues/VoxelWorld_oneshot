# M40 v2 — Inventory, Crafting and Character UI Overhaul

**Base:** `2afab28` on `codex/m34-canopy-composition`, clean working tree.
**Baseline:** unit `3043`, integration `491`, regression `52` assertions.

## Reproduced defects

1. **Character preview size** — measured in the running game:
   - before selecting a slot: `rect=(140, 236)`, viewport `(140, 236)`;
   - after `focus_slot(10)`: `rect=(148, 433)`, viewport `(148, 433)`.

   Cause: the item-details Label autowraps, so its minimum height grows with the
   selected item's text. The center panel and the body HBox grow, and the Player
   panel's `EXPAND_FILL` preview cell grows from 236 to 433. `CharacterPreview`
   then mirrors that rect into its SubViewport. Fix: fixed preview cell, no
   expand, and a scrollable fixed-height details pane so text cannot drive layout;
   stop mirroring the control size into the viewport manually.

2. **Left-click inconsistency / hidden one-item placement** — the current hotbar
   click does two things (select the hotbar slot *and* pick up the stack), which
   makes selection look like it failed and makes the held-state ambiguous. The
   new model separates concerns: clicks only move/select stacks; hotbar selection
   stays on 1–9/wheel. Right-click is the only one-item/half shortcut.

3. **Character opens crafting** — navigation currently routes Crafting through a
   separate overlay signal while Character is a page. The new route is three
   explicit pages in one screen: Inventory, Crafting, Character. Settings remains
   the existing overlay; Map stays disabled. No button may open another page.

4. **Crafting too simple** — replaced by a three-column recipe browser with real
   categories, search, recipe grid, details, ingredient availability, station
   requirements and quantity crafting.

## New architecture

- `InventoryPanel` owns one full-screen screen with three pages:
  - **Inventory**: Player panel + 6-wide inventory grid + item actions panel +
    hotbar/vitals/hints.
  - **Character**: the same Player panel and inventory grid + Stats panel;
    rotation controls; no crafting trigger.
  - **Crafting**: Categories | recipe browser + search | recipe details
    (3x3 preview, ingredients, station, quantity, Craft).
- Persistent Player panel and inventory grid across Inventory/Character so the
  preview and slots are never recreated.
- Fixed-size preview cell (`custom_minimum_size`, no vertical expand) and a
  fixed-height `ScrollContainer` for long details.
- Explicit interaction model:
  - LMB full-stack take/place/merge/swap; no hotbar selection side effect.
  - RMB half pickup / one placement.
  - Shift quick move; Ctrl+LMB select all; MMB opens the item actions menu;
    R opens the amount dialog; Esc closes and returns the cursor.
  - Right-click on the dim cancels the carried stack.
- Item actions panel + amount dialog:
  - Select All / Half / One / Amount, Quick Move, Move to Hotbar, Cancel.
  - Amount dialog: All/Half/One, numeric input, slider, Confirm/Cancel; range
    1..available; cancel is mutation-free; confirm transfers exactly the selected
    amount with normal stack limits.
- Crafting page uses `Crafting.recipes()` / `can_craft_times()` /
  `craft_many()` only; no recipe definitions in the UI. Categories are the real
  catalogue categories (All, Basics, Building, Tools, Smelting, Food); unsupported
  reference categories are hidden. Quantity max is computed from ingredients and
  output capacity. Station gating uses the game's nearby station.
- Character stats use real data: Health, Hunger, held-item Attack, player movement
  speed. Experience, defence and armour are not implemented and are labelled as
  such, never fabricated.

## Tests

- Rework `test_m40_inventory_ui.gd` for the new pages, context/amount dialog,
  recipe browser, quantity crafting and preview-stability regression.
- Add runtime checks for page navigation, preview rect stability after focus/page
  switches, real crafting, full/invalid transactions and hotbar sync.
- Keep the existing `CraftingPanel` unit tests as the model-level catalogue
  fixture; it is no longer reachable from the screen navigation.

## Evidence

Captures: main inventory, Character menu, Crafting menu with selected recipe,
amount dialog, 1280×720 and 1600×900. Update `m40-report.md`,
`PROJECT_STATUS.md`, `MILESTONES.md`; commit in the established style.
