# M40 — Inventory, Crafting and Gameplay UI

**Status: COMPLETE**, with the limitations listed at the end. The interface is
integrated into the running Godot game, interactive, covered by automated tests
and reviewed against runtime captures.

**Base:** `42a97b3` (`Consolidate project around Godot`), branch
`codex/m34-canopy-composition`, clean working tree before the work.
**Code commits:** `195b105` (`M40: implement inventory, crafting and gameplay UI`)
and `47fd5fa` (HUD hint clearance and refreshed captures).
**Evidence commit:** `13c574a` (report, screenshots, status and milestone record).
A follow-up commit gates polled WASD/jump input while an overlay owns the mouse.
**Canonical project:** `C:\Users\Admin\Documents\Projects\VoxelWorld_Godot`.
No other project copy, worktree or branch was created.

## What was implemented

### One inventory screen

`InventoryPanel` is now the full M40 experience described by the reference:

- top navigation with keycaps, drawn glyphs and the reference's selected-tab
  treatment;
- a Player panel with a real rendered voxel character (transparent SubViewport),
  four armour slots and two off-hand slots;
- the authoritative 27-slot storage grid plus the nine-slot hotbar;
- a real 3x3 crafting grid with an arrow, a result slot and a crafting-table
  note;
- contextual Controls card with only supported actions;
- live hearts/hunger vitals.

Every displayed number comes from `Inventory`, `Health` and `Survival`. The
screen never owns gameplay state.

### Inventory interaction

Preserved and extended the M20 interaction model:

- left click take/place, right click split/place-one;
- shift-click quick move between hotbar and storage;
- drag-and-drop inside the player grid;
- merging compatible stacks up to `ItemDB.max_stack`, swapping incompatible
  stacks, partial transfers and refused transfers;
- a temporary cursor stack that is returned to the inventory on close/save; a
  genuinely full inventory refuses to close instead of deleting the stack.

The transient crafting grid follows the same rules: its contents and result are
returned to the player on close/save, and a full inventory refuses the close.

### Crafting

The screen owns one transient `Station(TABLE)` and calls the existing
`Station.craft_grid()` transaction. No recipe logic exists in UI code:

- 3x3 matching uses `Station.matched_recipe()` / `Crafting.match_grid` and
  `match_shapeless_counts`;
- the result slot shows a live ghost preview of the matched output;
- the arrow (`craft_press`) crafts atomically; the result slot delivers the
  output, with shift-click sending it straight to the inventory;
- `Crafting.station_satisfied` gates table recipes by the real nearby station
  (`Crafting.best_station`), so a table recipe cannot be crafted by hand;
- an invalid grid, missing ingredients, a missing table and a full result slot
  are reported without consuming anything (verified by tests).

### Hotbar and HUD

- Nine numbered hotbar slots with real icons, stack counts, selection highlight
  and tool durability bars.
- The gameplay HUD is hidden while the screen is open (the screen has its own
  hotbar/vitals) and restored when the screen really closes.
- `GameHUD` now draws ten 2-point hearts and ten hunger units from the real
  `Health`/`Survival` values, plus the existing breath and mining readouts.
- Experience and level are **not** shown because VoxelWorld does not implement
  them. No fabricated value is displayed.

### Navigation and input

- Inventory and Character are pages of the screen; Crafting and Settings open the
  existing overlays; Map is visibly disabled with an explicit tooltip.
- `I` / `Esc` closing is unchanged; the screen owns the mouse while open and
  gameplay interaction stays disabled (existing game gate).
- The character page shows live health/hunger, the held item and an explicit
  "equipment is not implemented" statement.

### Icons

One `ItemIcon` control is now used by the inventory grid, hotbar, cursor,
crafting catalogue, station slots and the result preview:

- block items are drawn as the reference's isometric cubes from the real top and
  side textures in `TextureLibrary`, with one lighting rule (top bright, left
  mid, right dark) and nearest filtering;
- non-block items (tools, food, lumps, seeds) keep the existing transparent
  VoxelWorld art with a soft shadow;
- open/deco blocks (flowers, grass tufts) keep their flat silhouette instead of
  being forced into a cube.

No item uses an emoji, Unicode placeholder or unrelated icon. Item identity stays
`ItemDB.icon_key`; changing an icon does not touch gameplay.

**Asset sources:** the existing vendored Minetest-derived textures and the
in-project M21/M22/M29 procedural icons, all already recorded in
`godot/assets/texture_sources.json` and `godot/ASSET_MANIFEST.md`. No new
third-party asset was added. **Remaining placeholder gaps: none identified**; all
defined items resolve through the existing icon keys and block face keys. The
non-block icons are the game's existing 2D art, not newly rendered 3D models.

## Mapping to the reference

| Reference element | M40 implementation |
| --- | --- |
| Top tabs + keycaps | Nav bar with Inventory/Crafting/Character/Map/Settings, drawn glyphs, blue selected tab, `I`/`Esc` keycaps |
| Player + equipment | Rendered voxel character, four armour slots, two off-hand slots, held-item row |
| Inventory grid | 27 storage slots as 9x3 (the model's capacity) with icons and counts |
| Crafting panel | Real 3x3 grid, arrow, result slot, live status, crafting-table card |
| Hotbar | Nine numbered slots, blue selected border, icons, counts, durability |
| Health/hunger | Ten hearts and ten hunger units from the real models |
| Contextual hints | LMB/RMB/Shift/close card, only supported actions |
| Dimmed world | Full-screen translucent dim over the running world |

**Deliberate deviations:** the grid is 9x3 because VoxelWorld's storage is exactly
27 slots (the reference's 6x5 mock grid cannot represent it without empty
placeholders); Map, XP/level, equipment gameplay and item dropping are absent
because the game does not implement them.

## Defects and fixes

No pre-existing inventory/crafting rule defect was found: the `Inventory`,
`Crafting`, `Station` and `StationInventory` models already had the atomic
transactions, stack caps and station checks the milestone needs. The old interface
simply did not expose them (no nav, character, 3x3 grid or M40 presentation), and
the hotbar/HUD used text bars and flat face icons.

Implementation issues found during verification and fixed:

1. `Polygon2D` has no `mouse_filter`/`antialiasing_quality`; the icon renderer
   aborted and leaked RIDs in the first integration run. Removed those writes and
   guarded face indices.
2. A narrow vitals row let hunger units run under the hotbar; sizes/spacing were
   reduced so the row ends before the hotbar.
3. The control hint sat behind the hotbar strip and was unreadable over bright
   terrain; it now has a dark backing strip below the hotbar.
4. The character preview was squashed by a fixed SubViewport aspect and cropped
   at the feet; the viewport now follows the panel size and the camera frames the
   full body.
5. The transient crafting grid initially risked being omitted from saves; saves
   now use `flush_all()` (cursor + grid).
6. **Pre-existing input defect:** `VoxelPlayer._physics_process` polled WASD,
   jump and fly input directly, so the player could walk behind an open
   inventory/crafting/settings/station panel (or the pause menu) even though
   `_unhandled_input` correctly ignored gameplay actions. Polled movement now
   respects the same `can_interact` gate. A real-scene regression presses
   `move_forward` while the screen is open (velocity stays inert) and again after
   closing (movement returns).

## Automated verification

Commands (Godot 4.7.2, from the repository root):

```
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path godot --script res://scripts/tests/run_tests.gd
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path godot --script res://scripts/tests/run_integration.gd -- --straight-to-game
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path godot --script res://scripts/regression.gd
```

| Suite | Baseline | Final |
| --- | --- | --- |
| Unit (`run_tests.gd`) | 2923 assertions | **3043 assertions** |
| Integration (`run_integration.gd`) | 463 assertions | **491 assertions** |
| Regression (`regression.gd`) | 52 assertions | **52 assertions** |

`godot/scripts/tests/test_m40_inventory_ui.gd` adds 120 assertions covering:
moving between empty slots, merging, splitting, partial transfers, incompatible
stacks, full inventory, full target stacks, duplication/loss prevention, valid
stack counts, hotbar synchronisation, consumption, valid/invalid/missing/full
crafting, station gating, atomic failures, displayed quantities, empty slots,
grid return on close with a full inventory, equipment presentation, navigation
and real health/hunger display (and the absence of invented XP/level).

The runtime integration suite adds 28 assertions that open the real M40 screen
over the game, verify the HUD hand-off, prove polled movement is inert while the
screen is open, run a real grid craft, switch pages, close (restoring the
HUD/interaction and movement) and reopen with an empty grid.

## Runtime / visual verification

Actual game captures (not mockups) are in this directory:

- `m40-inventory-1280.png` — full screen at 1280x720, 35 real items, real table
  nearby, wood-pickaxe grid and live result preview.
- `m40-inventory-1600.png` — the same screen at 1600x900 (container/anchors, not
  hardcoded to one resolution).
- `m40-character-1280.png` — Character page with live Health 16/20 and Hunger
  13/20.
- `m40-hud-1280.png` — gameplay HUD with hearts/hunger, hotbar icons, durability
  and control hint over the world.
- `game-capture.json` — the 1280 capture metrics/hashes.

Capture command (representative):

```
Godot_v4.7.2-stable_mono_win64_console.exe --path godot -- --m40-capture \
  --capture-name=m40-inventory-1280.png --settle=5 --health=16 --hunger=13
```

Observed in the captures: the nav/tab hierarchy, panel proportions, dark
translucent panels with blue highlights, character/equipment layout, 9x3
inventory grid with isometric block icons and readable counts, real 3x3 craft
grid with output preview and table card, nine-slot hotbar with selection and
durability, hearts/hunger at the bottom-left, contextual hints at the
bottom-right, and a dimmed world behind. The 1600x900 capture confirms the layout
stays usable at a second supported resolution. No runtime errors or failed
resource loads occurred in the final capture or test runs.

## Limitations

- **Equipment:** VoxelWorld has no equipment/armour/off-hand gameplay. The six
  slots are present, disabled and honestly labelled; no items or mechanics were
  invented.
- **Experience/level:** not implemented, so not displayed. No XP bar or level
  number is shown.
- **Map:** not implemented; the tab is disabled with a "Map is not available yet"
  tooltip.
- **Item dropping:** not an existing mechanic, so the reference's Q/drop hint is
  not offered. The hints list only supported controls.
- **Grid shape:** 9x3 for the 27-slot storage model rather than the reference's
  6x5 mock grid.
- **Icon depth:** block icons are isometric cubes; non-block items reuse the
  existing flat 2D art rather than newly rendered 3D models. They are coherent,
  correctly mapped and not placeholders.
- **Background:** the world is subdued with a translucent dim, not blurred. The
  brief permits "blurred or visually subdued".
- The character preview is a first-party voxel model built for this screen
  because the first-person game has no exported player model; it is not the
  reference's exact character.

## Recommended next steps

1. Add an equipment model and armour items, then enable the six slots and draw
   equipped gear on the preview.
2. Add experience/levels with a real XP source and a HUD display.
3. Add a map screen (or keep the tab disabled).
4. Consider 3D-rendered icons for tools/food if the flat art becomes the visual
   bottleneck.
5. Consider a blur pass for the dimmed world if the visual brief is tightened.
