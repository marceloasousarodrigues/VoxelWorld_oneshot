# M40 — Inventory, Crafting and Gameplay UI

**Base:** `42a97b3` (`Consolidate project around Godot`), branch
`codex/m34-canopy-composition`, clean working tree. Unit baseline
`M17_TESTS_PASS 2923 assertions`; integration baseline `463 assertions`.

**Reference:** the approved inventory screenshot supplied with the M40 brief.
The reference is the visual authority, not the item catalogue.

## Scope

One full-screen inventory experience integrated into the running game:

- top navigation (Inventory, Crafting, Character, Map, Settings),
- player panel with a rendered voxel character preview and equipment slots,
- the real 27+9 player inventory with click / split / quick-move / drag,
- a 3x3 crafting grid with output preview, station gating and atomic crafting,
- nine-slot hotbar with selection, counts and durability,
- real health/hunger vitals (no invented XP or level),
- contextual interaction hints that only list supported controls.

## Decisions

- **Grid shape:** inventory stays 27 main + 9 hotbar (authoritative model). The main
  inventory is drawn as 9x3 because that maps one cell to one model slot; the
  reference's 6-wide mock grid cannot represent 27/36 slots without empty
  placeholders.
- **Crafting:** the screen owns one transient `Station(TABLE)` and reuses
  `Station.craft_grid()` / `Crafting`; no recipe logic is duplicated in the UI.
  Table recipes are gated by the real nearby station (`Crafting.best_station`).
- **Equipment:** VoxelWorld has no equipment/armour system. The four armour and
  two off-hand slots are presentational, explicitly disabled, and documented;
  no equipment gameplay is invented.
- **XP/level:** not implemented in VoxelWorld. The HUD shows health and hunger
  only; no fabricated experience value.
- **Navigation:** Inventory/Character are pages of this screen; Crafting and
  Settings open the existing overlays; Map is disabled with a "not available"
  tooltip.
- **Icons:** a single `ItemIcon` control draws block items as isometric cubes from
  the existing top/side textures (per-face lighting) and non-block items from the
  existing transparent icon art, with one shared size/padding rule. Item identity
  remains `ItemDB.icon_key`; presentation is isolated in `ItemIcon`.

## Files

- `godot/scripts/game/item_icon.gd` — isometric/flat icon control.
- `godot/scripts/game/nav_icon.gd` — drawn navigation glyphs.
- `godot/scripts/game/character_preview.gd` — SubViewport voxel character.
- `godot/scripts/game/vitals_bar.gd` — hearts/hunger/breath, shared by HUD/screen.
- `godot/scripts/game/ui_style.gd` — M40 palette, panel/slot/tab styles.
- `godot/scripts/game/inventory_panel.gd` — the unified screen (existing public
  API kept; crafting grid, nav, character page, hotbar, hints added).
- `godot/scripts/game/game_hud.gd` — reference-style hotbar and vitals.
- `godot/scripts/game/game.gd` — station/vitals/nav wiring, capture loadout.
- `godot/scripts/game/inventory_slot.gd`, `item_cursor.gd`,
  `station_slot.gd`, `crafting_panel.gd` — shared `ItemIcon`.
- `godot/scripts/tests/test_m40_inventory_ui.gd` — new M40 suite.
- `godot/scripts/tests/run_tests.gd` — register the suite.

## Verification

1. New suite red, then green; full unit suite; integration suite; regression.
2. Runtime capture with `--capture --m40-capture` at 1280x720 and a second
   resolution; inspect the PNGs against the reference.
3. Character page capture.
4. Update `PROJECT_STATUS.md`, append the M40 milestone record, commit.

## Out of scope

Forest generation, M38/M39, equipment gameplay, item dropping, XP/level systems,
map screen.
