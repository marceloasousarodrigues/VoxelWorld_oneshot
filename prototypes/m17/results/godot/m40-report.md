# M40 — Inventory, Character and Crafting UI Overhaul

**Status: COMPLETE**, with the limitations listed at the end. This report covers
the final M40 overhaul; the earlier inline-grid M40 screen is superseded.

**Base:** `2afab28` (the previous M40 input-gate commit), branch
`codex/m34-canopy-composition`, clean working tree.
**Code commit:** `c6bc97b` (`M40: overhaul inventory, character and crafting UI`).
The v1 implementation remains in history (`195b105`, `13c574a`, `47fd5fa`,
`c4ac3c5`, `2afab28`) and is replaced by this work.
**Canonical project:** `C:\Users\Admin\Documents\Projects\VoxelWorld_Godot`.
No other project copy, worktree or clone was created.

## Root causes of the reported defects

### A. Character preview changed size

Reproduced in the running game. The old layout measured:

```
before selecting a slot: rect=(140, 236), viewport=(140, 236)
after  selecting a slot: rect=(148, 433), viewport=(148, 433)
```

Cause: the item-details Label autowraps, so its minimum height grew when the
selected item changed from "no item selected" to a long tool/block description.
That grew the centre panel, then the body HBox, and the Player panel's
`EXPAND_FILL` preview cell expanded from 236 to 433 px. `CharacterPreview`
mirrored the control rect into its SubViewport (a `resized` handler), so the
rendered character grew too.

Fix: fixed-size preview cell (`200×290`, no vertical expand), a fixed-height body
layout that fills the available space rather than being sized by content, a
fixed-height `ScrollContainer` for long facts, and removal of the
control-size → viewport-size feedback. The preview rect is now exactly stable
across slot focus, item-action opening, Character/Crafting tab switches and
reopening. The regression asserts the full rect, not just the image size.

### B. Inconsistent stack selection / one-item placement

The old inventory auto-selected a hotbar slot **and** picked up its stack on the
same click, so a click could look like a failed selection, a pick-up, or a
one-item transfer depending on the previous cursor state. The explicit model now
separates the concerns:

- click only moves/selects stacks; it never changes the held hotbar slot;
- hotbar selection remains 1–9 / mouse wheel during gameplay;
- one-item and half-stack actions only happen through right-click or the explicit
  quantity controls, never as a hidden side effect of a full-stack left click.

### C. Character menu opened crafting

Crafting used to be a separate overlay reached by a navigation signal, while
Character was a page. The three experiences are now **internal pages of one
screen**: Inventory, Crafting and Character. The Crafting tab and the C key both
open the Crafting page; the Character tab opens Character and has no crafting
callback. The legacy crafting overlay is not opened by the navigation or by C.

### D. Crafting was too simple

The old screen exposed a single 3x3 grid and the old catalogue overlay listed
recipes without selection, search, quantities or rich details. The Crafting page
is now a full three-column browser backed by the authoritative `Crafting`
catalogue.

## Implemented UI

- **Navigation**: Inventory / Crafting / Character / Map / Settings, with the
  reference's blue selected tab and `I`/`Esc` keycaps. Map is explicitly disabled;
  Settings opens the existing settings overlay.
- **Player panel**: stable rendered voxel character, four armour slots, two
  off-hand slots, held-item row, Character-page rotation controls (`‹ • ›`) and
  an honest equipment note.
- **Inventory**: 27 storage slots in a 6-column grid plus the nine-slot hotbar.
  Real icons, counts, durability indicators and selection.
- **Item actions card**: the reference's context menu, with only valid actions:
  Select All, Select Half, Select One, Select Amount…, Quick Move, Move to
  Hotbar (storage slots), Cancel.
- **Select Amount dialog**: item icon, available/carrying counts, All/Half/One,
  numeric entry, slider, live amount, Confirm/Cancel. Range is clamped to the
  actual transferable quantity; Cancel is mutation-free.
- **Character page**: the same stable Player panel and inventory grid plus a
  Stats panel with real Health, Hunger, held-item Attack and Movement Speed.
  Experience, defence and armour are explicitly marked as not implemented rather
  than fabricated.
- **Crafting page**: categories from the real catalogue (`All`, Basics, Building,
  Tools, Smelting, Food), search, scrollable recipe grid with selected/available
  state, and a details panel with output, 3x3 recipe pattern, ingredients and
  have/need counts, station requirement, quantity `− / +` with Max, status and
  Craft.
- **Hotbar/HUD**: nine numbered slots, selected highlight, counts, tool
  durability; real hearts and hunger units; the existing HUD is hidden while the
  screen owns the mouse and restored when the screen really closes.

## Interaction model (documented in the UI)

| Input | Behaviour |
| --- | --- |
| LMB | Take/place the **full** stack; merge or swap; no hotbar-selection side effect |
| RMB | Split `ceil(half)` into the cursor, or place exactly one |
| Shift+LMB | Quick move between hotbar and storage |
| Ctrl+LMB | Select All (full stack) |
| MMB | Open the item actions card for that slot |
| R | Open the Select Amount dialog for the focused slot |
| Esc | Cancel dialog/menu or return the carried stack; next Esc closes |
| RMB outside the panels | Return the carried stack / close the menu |
| 1–9 (gameplay) | Select a hotbar slot |

The cursor stack is temporary UI state. It is returned to the inventory on close
or save; a genuinely full inventory refuses the close instead of deleting it.

## Crafting and data integrity

- The Crafting page uses `Crafting.recipes()`, `ingredients()`, `fuel()`,
  `can_craft_times()`, `craftable_count()` and `craft_many()`. No recipe is
  redefined in UI code.
- Category and search filters operate on the real catalogue.
- The maximum craft quantity is the largest count whose ingredients/fuel and
  output capacity both fit; it accounts for slots freed by consuming inputs.
- `Crafting.craft_many()` is atomic: invalid, missing, station-blocked or
  full-output crafts consume nothing.
- Station gating uses the game's real nearby station (`Crafting.best_station`),
  passed in by the game.
- Item moves use the existing `Inventory` full-stack/merge/swap/quick-move
  primitives; the amount dialog uses the same stack caps and conservation rules.

## Icons and assets

Block items are isometric cubes drawn from the existing top/side textures in
`TextureLibrary`, with one lighting rule. Non-block items use the existing
transparent VoxelWorld art with a shadow; open/deco blocks stay flat. Sources are
the existing vendored Minetest-derived textures and in-repo M21/M22/M29
procedural icons recorded in `godot/assets/texture_sources.json`; no new
third-party dependency or asset was added. No item uses an emoji or unrelated
symbol. Remaining art limitation: non-block items are the game's existing 2D art,
not newly rendered 3D icons.

## Automated verification

Commands (Godot 4.7.2, from the repository root):

```
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path godot --script res://scripts/tests/run_tests.gd
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path godot --script res://scripts/tests/run_integration.gd -- --straight-to-game
Godot_v4.7.2-stable_mono_win64_console.exe --headless --path godot --script res://scripts/regression.gd
```

| Suite | Before this pass | Final |
| --- | ---: | ---: |
| Unit | 3043 | **3092 assertions** |
| Integration | 491 | **503 assertions** |
| Regression | 52 | **52 assertions** |

The M40 suite covers full/half/single/arbitrary-quantity moves, merging,
swapping, partial and full inventories, invalid destinations, context actions,
amount-dialog boundaries and cancel, quick move, hotbar synchronisation,
duplication/loss conservation, recipe selection, category/search filters,
missing ingredients, exact consumption, quantity maxima, repeated crafting,
full output, atomic failure, table/furnace gating, the Character stats, distinct
navigation, repeated tab switching and exact preview-rect stability.

The runtime suite adds 12 checks over the previous M40 section: real-scene page
routing, the HUD hand-off, movement inert while open (and restored after),
preview stability across focus/actions/Character/Crafting/return/reopen, a real
recipe-browser craft, the amount dialog and the R shortcut, and the legacy
crafting overlay staying closed.

## Runtime / visual verification

Actual running-game captures (not mockups):

- `m40v2-inventory-1280.png` — main inventory with the 64-item Grass actions
  card, 6x5 grid, stable character preview, hotbar, hearts/hunger, controls.
- `m40v2-inventory-1600.png` — the same screen at 1600x900.
- `m40v2-character-1280.png` — distinct Character page with the shared Player
  panel, inventory and real Stats.
- `m40v2-crafting-1280.png` — Tools category, selected wood pickaxe, 3x3
  pattern, station, ingredients and quantity.
- `m40v2-crafting-missing-1280.png` — missing Gold Lump state, Max 0 and a
  disabled Craft button.
- `m40v2-amount-1280.png` — Select Amount dialog over the inventory.
- `m40v2-hud-1280.png` — error-free gameplay HUD.
- `m40v2-preview-bug-before.png` / `m40v2-preview-bug-after.png` — the
  reproduced old defect (the preview grew from 236 to 433 px after selection).

The fixed preview rect measured `(148, 119, 200, 290)` and stayed byte-for-byte
the same across the runtime focus/actions/Character/Crafting/return/reopen
checks.

No runtime errors or failed resource loads occurred in the final captures or
test runs.

**Not directly verified:** no human mouse/keyboard play session was performed.
Interactions were driven through the same handlers a mouse invokes, including
real mouse-button events for middle-click/Ctrl in the unit suite, and polled
movement was driven programmatically in the runtime suite. The visual review was
an inspection of the rendered captures against the supplied references.

## Limitations

- **Equipment, experience, defence and armour** are not implemented in
  VoxelWorld. Equipment slots are display-only; experience/defence/armour show an
  explicit "not implemented" note instead of values.
- **Map** is disabled with a tooltip; **Use**, **Drop** and **Move to Chest** are
  not offered because those mechanics do not exist.
- The **legacy `CraftingPanel`** class and its unit tests remain for the existing
  model-level test surface and the `--open-crafting` diagnostic. It is not
  reachable from the tabs or the C key; the user-facing crafting menu is the new
  page.
- The storage grid is 6 columns × 5 rows because the model has 27 slots (the last
  row is partial); the reference's mock grid is wider than that capacity.
- Non-block icons are the existing 2D assets, not newly rendered 3D icons.
- No formal performance benchmark was run. The preview now uses
  `UPDATE_WHEN_VISIBLE`, the hidden screen skips inventory-driven rebuilds, and
  the screen's static controls do not add per-frame work beyond the existing
  vitals updates.

## Recommendations

1. Add an equipment model and armour items, then enable the six slots and draw
   equipped gear on the preview.
2. Add experience/levels with a real source and show them in Stats/HUD.
3. Add a map screen, item dropping and chest-adjacent inventory actions if those
   mechanics are introduced.
4. Consider 3D icons for tools/food if the existing 2D art becomes the visual
   bottleneck.

## Git

The final working tree is clean. M40 v2 code and tests are in `c6bc97b`; the
evidence/report commit follows it. The earlier M40 v1 commits remain in history
and are superseded by this overhaul.
