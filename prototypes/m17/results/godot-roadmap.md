# M17 Godot — Roadmap

Status legend:

- `[x]` implemented **and verified** (automated test or inspected runtime/visual evidence)
- `[~]` implemented, not yet verified
- `[ ]` not started
- `[!]` blocked

Source of the phase structure: `prototypes/m17/GODOT_MISSION.md` §8.

---

## M29 — Starter house near spawn (post-endgame user request)

Evidence: `godot-progress.md` M29 section; `starter-house-spawn.png`,
`starter-house-close.png`; `scripts/game/starter_house.gd`;
`test_starter_house.gd`.

- [x] A fresh world builds a **complete cottage** at `spawn + (-6, -9)` — the
      default spawn look direction — before play starts
- [x] Stone foundation, timber frame, plank infill, glass windows, door, stepped
      tiled stair roof with ridge/chimney, interior table/furnace/chest/barrel,
      hanging lantern and a lit door lantern
- [x] A packed path connects the door to the spawn column; the footprint is
      levelled to the spawn ground and the spawn foot/head cells stay clear
- [x] The house is written through the normal block API and **recorded as player
      edits**, so it saves, reloads and streams like player building
- [x] Loaded saves are not modified; the showcase/build/final demos skip it
- [x] Gate: unit **2042** / integration **438** assertions, both exit 0; smoke
      twice `edits=502`, `world_hash=7225730083801702457`
- [~] Fixed template (no procedural variation); no human play-through
- [ ] Door open/close interaction remains future work

---

## M28 — Final playable loop and release-quality pass

Evidence: `godot-progress.md` M28 section; `m28-final-{wide,village,castle,dusk,night}.png`;
`scripts/game/final_demo.gd`; `test_final_demo.gd`; `run_integration.gd::_final_journey_section`.

- [x] **End-to-end scripted journey through the real systems**: `test_economy.gd`
      proves an empty inventory can harvest → craft tools/table/furnace →
      mine/smelt → craft the whole build kit; the final demo then builds a home,
      longhouse, market stalls, tower, village street/gardens/well/lanterns and a
      castle from that palette, and the integration section saves + reloads it
      with the player position and structures intact
- [x] The final settlement is **player-built**: every cell is written through
      `world.set_block`/`set_block_state`, recorded as a player edit, mineable,
      streamed and saved; no `StructureDB` stamp or showcase-only model
- [x] The starting site is natural and outside the levelled settlement area; the
      ring of framing trees ties the village into the generated landscape
- [x] Menus/HUD/inventory/recipes/controls/pause/death/respawn/save-load remain
      covered by the existing integration sections and HUD help/prompt text
- [x] Final gate: unit **2026** / integration **438** assertions, both exit 0;
      smoke twice `world_hash=5222532724760257225`; M27 settle p95 5.108 ms /
      p99 8.288 ms remains the performance baseline
- [x] Windowed visual review of broad village/castle, close castle, dusk and
      night captures
- [~] No human keyboard/mouse play-through; the journey is scripted through the
      real APIs, and the site is levelled by the harness
- [ ] Known non-blocking gaps: canopy carpet at distance, visible loaded-region
      edge on long sea views, no generated gorge terraces, no audio/weather,
      no city-management layer, no dropped-item entity for a full inventory

---

## M27 — Bring normal generated worlds closer to the visual references

Design/evidence: `godot-progress.md` M27 section; `m27-before-*` (pre-tuning)
and `m27-normal-{broad,inland,close,dusk}.png`, `m27-build-{wide,cottage,tower}.png`.

- [x] Reference observations recorded for all three supplied images
- [x] **Shallow-water checkerboard fixed**: water culls its face against solids
      instead of emitting coplanar transparent quads over the seabed
- [x] Water depth/opacity/tint retuned; animated texture reduced to a subtle
      grain; clean deep-blue basin with a readable shoreline
- [x] Sky/haze: deeper horizon, brighter/stronger clouds, fog colour matched to
      the ground horizon, stronger aerial perspective
- [x] Foliage: oak/pine leaf art restored to a real cutout (the M18 pass had
      made it fully opaque), internal leaf shading, AO on cutout leaves, per-tree
      lean/ragged crowns/lower skirt, stronger per-cell and macro green variation
- [x] Denser ground cover and stone exposed from slope ≥ 3
- [x] Fixed-seed normal-world broad/close/inland/dusk captures plus the
      player-built cottage/tower in its natural setting, all inspected
- [x] Gate: unit **2005** / integration **429** assertions, both exit 0; smoke
      twice `world_hash=5222532724760257225`; settle p95 5.108 ms / p99 8.288 ms
      (at or below the M22 baseline) in `perf-settle-m27.json`
- [~] No human play-through; fixed scripted viewpoints only
- [ ] Remaining gaps: canopy still reads as a carpet from high above (reducing
      density broke the NPC test), loaded-edge line on long sea views, no
      dramatic generated cliff terraces, striped Ore Outcrop landmark

---

## M26 — Protect player-built worlds through saving and streaming

Evidence: `godot-progress.md` M26 section; `scripts/tests/test_m26_protection.gd`.

- [x] Save/reload retains player position/flying, inventory (blocks, ingots,
      crafted tool), clock, health, breath, hunger, placed and removed blocks,
      stairs orientation, station contents and resident/settlement payloads
- [x] **Multi-chunk build** (x=15/16 boundary: masonry, glass, removed block,
      two oriented stairs, table, door) survives write → fresh-world apply →
      far-half unload/regeneration → `clear_edits()` → re-apply → read-from-disk
      restart, with no lost or duplicated blocks
- [x] Older saves: v1–v8 load (v8 rows default orientation to 0); invalid
      payloads are rejected and quarantined; a rejected save leaves the live
      world fingerprint and player untouched
- [x] **Recoverable atomic write**: the old save is moved to `.bak` across the
      finalise rename, restored if finalise fails, and recovered by `read()`
      after an interrupted run; `.tmp`/`.bak` are cleaned by `delete_save`
- [x] Visual test and build demo remain isolated from normal saves, autosave and
      quit-save
- [x] Gate: unit **2004** / integration **429** assertions, both exit 0; smoke
      twice `world_hash=2065363152372568468` unchanged
- [~] No human quit/restart play-through; restart is simulated through the real
      `SaveManager` path
- [ ] Performance not re-benchmarked because no meshing/streaming/generation
      code changed (save-file management only); M25 baselines stand

---

## M25 — Expressive, dependable construction

Design/evidence: `godot-progress.md` M25 section; `m25-build-wide.png`,
`m25-build-cottage.png`, `m25-build-tower.png`, `m25-build-dusk.png`.

- [x] Compact architectural set confirmed against the references and current
      assets: stone foundation/masonry, timber frame/posts, plank infill, glass,
      door, packed path, stairs/roof tile/ridge, fence (a gap is the gate),
      lantern, and table/furnace/chest/barrel props
- [x] **Stair rotation (`R`)** cycles an explicit facing that overrides the
      camera; placing on an underside still flips the stair
- [x] **Live build feedback**: selected material, aimed face, remaining count,
      resulting stair facing and a valid/blocked reason, derived from the same
      preview the placement path uses; controls documented in the HUD
- [x] Placement still refuses occupied cells and the player body; mining and
      building use only the affected chunk + seam invalidation (existing
      `test_edit_rebuild.gd` and streamer integration)
- [x] **Player-authored demonstration**: `build_demo.gd` levels a natural site
      and writes a cottage and a stone/timber tower cell by cell through the
      real block API — no `StructureDB` stamp and no showcase-only model
- [x] Tests: `test_build_demo.gd` (materials, both roof-slope orientations,
      ridge, furnishings, mineability), stair rotation/preview cases, and 3
      real-scene HUD integration assertions
- [x] Gate: unit **1943** / integration **429** assertions, both exit 0; smoke
      twice `world_hash=2065363152372568468` unchanged; four windowed captures
      inspected
- [~] No human keyboard/mouse build; the demo is scripted through the real API
- [ ] Slabs/corner stairs remain a future comfort feature; M28 builds the final
      village/castle journey

---

## M24 — Exploration yields a useful building economy

Design/evidence: `godot-progress.md` M24 section; `scripts/tests/test_economy.gd`.

- [x] **Fixed the gravel dead end**: `WorldGen` never produced gravel while
      `packed_path` required it, so paths were unobtainable. The submerged
      subsurface band now yields clay or gravel deterministically (20 % each)
- [x] **Generated-source scan** proves every core raw material actually appears
      in normal seed-17017 terrain: wood, dirt/stone, sand, clay, gravel, coal,
      iron
- [x] **Empty-inventory route** reaches the whole build kit using the real
      `ItemDB.harvestable` gate and `Crafting` transactions at a real
      `Crafting.best_station` table/furnace: planks, sticks, table, wooden
      pickaxe, stone, furnace, coal, stone pickaxe, iron, ingots, sand, clay,
      gravel, dirt, timber framing, stairs, fence, door, stone brick, path,
      glass, roof tiles, barrel, lantern
- [x] Tool gates confirmed along the route: bare hand refuses stone; wooden
      pickaxe refuses iron ore; stone pickaxe mines it
- [x] Starter kit audited: no tools, ingots, ore or furnace; every granted item
      is independently reachable
- [x] Inventory capacity/feedback, atomic batches and recipe labels remain
      covered by `test_crafting.gd`; the route consumes exactly the costs it
      asserts (e.g. the 4-ingot lantern)
- [x] Gate: unit **1912** / integration **426** assertions, both exit 0; smoke
      twice `world_hash=2065363152372568468` (new gravel baseline),
      `faces`/`faces_hash` unchanged, identical runs
- [~] No human play-through; the route is a deterministic harness over the real
      rules plus the existing scripted real-scene crafting/mining checks
- [ ] A player-authored home site is demonstrated in M25/M28; M24 only proves
      the materials and freedom to choose the site

---

## M23 — Roof stairs and stair behavior

Design/evidence: `godot-progress.md` M23 section; captures `m23-stairs-roof.png`,
`m23-stairs-profile.png`, `m23-stairs-dusk.png`.

- [x] `Stair` block id 88, planks faces, solid/opaque, hardness 1.8 and a
      self-drop; recipe `3 planks + 1 stick → 2 stairs` at a crafting table
- [x] `core/block_shape.gd`: eight orientations (four facings × upright/upside
      down), half-cell occupancy, boundary masks and exposed-face enumeration;
      verified canonical mask `0x3F`, 6 half-cells, 22 exposed faces
- [x] Placement orientation follows the aimed face and the player's horizontal
      look (downward hits flip the stair); placement refuses inside the body
      using the actual half-cell occupancy
- [x] Shaped meshing: render and collision come from the same 22 half-cell
      faces; adjacent full cubes keep only the uncovered half-face patches and
      adjacent stairs cull only overlapping half-faces, including across chunk
      seams (worker snapshots carry orientation)
- [x] Half-cell voxel DDA targeting: rays pass through the empty half of a stair
      and stop on the internal riser with its real normal; mining returns the
      stair item and clears the orientation
- [x] Save VERSION 9 stores orientation per edited block; v1–v8 saves load with
      orientation 0 and are rejected per-row if a pre-v9 row carries orientation;
      unload/regeneration replays orientation
- [x] Tests: `test_block_shape.gd`, `test_stair_interaction.gd`, stair cases in
      the mesher/raycast/edits/persistence/crafting tests and 24 real-scene
      integration assertions
- [x] Visual: showcase stair-roofed pavilion (two stair slopes + ridge) with
      `--visual-test=roof|stairs`; first pass exposed a floating ridge and the
      ridge was moved onto the inner stair row
- [x] Milestone gate: unit **1852** / integration **426** assertions, both exit
      0; smoke twice `world_hash=7821043820538758500` unchanged; three windowed
      captures inspected
- [~] No live human keyboard/mouse stair placement; scripted real-controller and
      showcase evidence only
- [ ] Slabs and stair variants (e.g. corner/outer stairs) remain future work

---

## M22 — Stylized voxel world: lush fantasy and medieval settlements

Design contract: `m22-visual-design.md`; evidence: `m22-progress.md`.

- [x] **20 procedural M22 textures** (birch, blossom, bush, three flowers,
      timber frame, roof tile/ridge/eave, path, lantern, fence, barrel, door)
      generated by `tools/generate_m22_textures.py`, packed into the shared
      `Texture2DArray`; no external download
- [x] **Material/palette pass**: warmer timber, terracotta roof tops and tile
      eave faces, earthy path, sage forest palette, stronger grass-side grading,
      low-frequency 24-block grass/foliage hue variation, blue sky and reduced
      horizon/fog wash, subtle lantern glow
- [x] **Terrain integration**: steep slopes expose stone (≥4) or dirt (≥2)
      instead of green carpet; wildflower/bush decoration in forest, plains and
      savanna; flowers keep their own colour; support removal clears plants when
      the block beneath is mined
- [x] **Vegetation library**: oak, pine, birch and rare blossom trees using one
      deterministic shape function; three flower colours and bushes with
      three/four crossed planes; fallen logs, worn-earth patches and boulders
- [x] **Medieval block vocabulary**: timber frame, tiled roof, roof ridge,
      packed path, lantern, fence, barrel, door, with craft recipes for the
      whole set (roof tiles fired in a furnace)
- [x] **Reusable architecture definitions**: `timber_cottage` (stone foundation,
      timber walls, glass windows, two-block door, tiled hip roof with eaves,
      ridge, chimney, furnished interior) and `market_stall`; both appear in the
      normal deterministic structure scan. `StructureDB.stamp()` writes the same
      definitions into the showcase
- [x] **Custom models**: barrel, lantern with emissive panes, neighbour-aware
      fence (log post + rail texture), plus the existing table/furnace/chest
- [x] **Bounded lantern lighting**: `game/lantern_lights.gd` tracks lanterns
      from chunk/edits signals and reuses ≤12 warm `OmniLight3D`s; fades by day
      and unregisters on chunk unload. Covered by 10 real-scene integration
      assertions
- [x] **Playable showcase** (`--visual-test`): 31×31 clearing, winding path,
      cottage, market stall, outdoor work area, pond + stream, plank bridge,
      fence/gate, lantern posts, four tree species, flower beds and rocks;
      isolated from saves/creatures/NPCs/raids
- [x] **Tests**: unit **1767 assertions**, integration **402 assertions**, both
      exit 0 with no script errors or assertion failures; smoke hash deterministic
      (`7821043820538758500`, 174353 faces, two identical runs); all new block,
      structure, mesh, recipe, decoration-support, persistence and light-pool
      paths covered
- [x] **Performance**: after look/settle/walk p95 3.40 / 5.30 / 4.86 ms vs
      baseline 3.50 / 5.90 / 5.11 ms; p99 also at or below baseline; draw calls
      effectively unchanged; cross phase p99 5.81 ms, worst 24.1 ms
- [x] **Windowed evidence inspected**: `m22-wide-noon.png`, `m22-normal-noon.png`,
      `m22-close-noon.png`, `m22-cottage-noon.png`, `m22-garden-noon.png`,
      `m22-bridge-noon.png`, `m22-dusk.png`, `m22-night.png`, four-frame
      `m22-tour-0..3.png`
- [~] Live keyboard/mouse play-through and video rotation inspection remain
      outstanding (same limitation as M18–M21); movement was inspected through
      the scripted tour
- [x] Next architecture step: roof stairs delivered in M23 (slabs remain a gap)
- [ ] Next settlement step: cluster cottages/stalls with a procedural path
      network instead of isolated definitions

---


## M21 — Gameplay depth, survival and progression

- [x] Data-driven creature definitions and loot (`core/creature_db.gd`):
      species name, health and weighted `{item, min, max, chance}` drop tables.
      A boar drops raw meat, hide and (70 %) a bone; a grunt drops bones and
      (50 %) coal. **The reported Oak Log boar drop is gone** and no species can
      leak another species' item ids. Loot is deterministic per kill cell and is
      awarded exactly once through the shared inventory path
- [x] Animal, cooking and farming items: Raw Meat, Cooked Meat, Hide, Bone,
      Wheat Seeds, Bone Meal, with real food values (raw 2, cooked 8 + 1 health)
- [x] Cooking chain: furnace `1 Raw Meat + fuel → 1 Cooked Meat` (5 s), using
      the existing timed `Station`/`Smelting` data path. Verified through a real
      timed furnace, not a menu shortcut
- [x] Wheat farming: `Farming` model + farmland and four crop-stage blocks.
      Plant seeds on grass/dirt (tills to farmland), crops grow every 24 s while
      loaded and nearby, ripe crops yield 2–3 Wheat + 1–2 Seeds, immature crops
      return one seed, unsupported crops are cleared. Growth progress persists
      (save VERSION 8) and crop block state persists through the existing edits.
      Right-click planting and left-click harvesting run through the real player
      controller; bone meal advances a crop one stage
- [x] Persistent storage chest: craftable from eight planks at a table, custom
      chest model, 27-slot `Station` storage with the existing cursor/quick-move
      rules. Contents survive close, save/reload, chunk unload and breaking
      (contents return to the player)
- [x] Tool progression re-verified end to end: a bare hand **cannot mine stone
      at all**; a wooden pickaxe **cannot mine iron ore at all** (the block stays
      in the world); a stone pickaxe yields the lump; tool wear and breaking are
      unchanged.  This supersedes the earlier "break now, no drop" rule: no
      progress, no block removal and no durability is spent on a refused break,
      and the HUD names the minimum tier/tool (`Iron Ore needs a Stone Pickaxe`)
- [x] UI/HUD: chest interface reuses the station panel (27 slots, persistent
      storage notes); crop and chest blocks have icons and real textures. Capture
      aids `--farming-capture` and `--station-capture=chest` reproduce the views
- [x] Tests: `test_m21_gameplay.gd` (loot, cooking, farming, chest + recipe),
      updated item/block/creature/hostile/persistence/crafting tests, and real
      scene integration for boar loot, planting → save/reload → growth →
      harvest, timed cooking, chest UI, chest persistence and chest recovery
- [x] Verification: unit **1693 assertions**, integration **391 assertions**,
      both exit 0 with no script errors or assertion failures; headless smoke starts and reports
      `world_hash=7995773462820745781` (untouched generation unchanged);
      inspected `m21-farming.png` (four crop stages, farmland, chest model) and
      `m21-chest.png` (27-slot storage UI); look p95 2.32 ms / settle p95 6.18 ms
      in `perf-{look,settle}-m21.json` (within the M18/M19 range)
- [~] No human keyboard/mouse play-through of the new farming/chest interactions
- [ ] Remaining M21 depth: equipment/armour slots, hostile species variety,
      village storage access, weather; see the Phase C/D entries below

---

## M20 — Inventory, hotbar, crafting and interaction overhaul

- [x] Authoritative 27 storage + 9 hotbar inventory model (`SIZE = 36`), with only
      the hotbar selectable as the held item.  Starter kit fills the hotbar only,
      leaving all storage free (root cause of “mined iron does not appear”)
- [x] Temporary cursor stack replaces the permanent carrying slot in the player
      inventory and station interfaces; left/right click, shift-click and drag &
      drop use the same model operations and conserve counts and durability
- [x] Cursor recovery on close: origin slot → any player slot → station; a full
      container keeps the panel open with an explicit message instead of deleting
- [x] Minecraft-like `I` inventory: 9×3 storage above the hotbar, selected-slot
      highlight, counts, durability, tooltips, item facts and shared M18 styling
- [x] Hotbar selection by 1–9 and mouse wheel; only the selected hotbar item is
      used by mining, building, eating and tool wear.  Opening/closing overlays
      never changes the selection
- [x] Station targeting from the existing voxel ray with range, prompt/outline,
      E to open, Esc/E to close, blocked world input and safe invalid/unloaded
      targets.  Verified from top-down and diagonal angles at range
- [x] Crafting table: one ingredient per grid cell per click/drag/shift-click;
      real 3×3 shaped (with horizontal mirroring) and shapeless matching; live
      result preview/status, atomic craft and full-result refusal.  **M20
      stabilization** makes shapeless matching quantity-aware, so eight
      cobblestone stacked in one cell craft a furnace exactly like eight spread
      across cells; shaped recipes keep the per-cell rule
- [x] Furnace: input/fuel/output timed processing verified through the rebuilt
      panel, with fuel, output-full pause, progress and persistence coverage
- [x] One crafting model: the C catalogue and the world-object panels share the
      same `Crafting` catalogue and atomic transaction.  **M20 stabilization**
      restores station-gated crafting in the catalogue (the earlier build only
      pointed at E, which made eight cobblestone appear uncraftable), and removes
      the duplicate `quick_move`/`put_one` ownership bugs
- [x] Save VERSION 7: 36-slot inventory, legacy nine-row saves load into the
      hotbar, storage rows round-trip, oversized payloads rejected
- [x] **M20 stabilization mesh fix**: `BlockDB.open_model` prevents the
      open-legged table and furnace from culling the ground/neighbour faces they
      do not cover, so the stone face under the table is rendered again.  Pinned
      by `test_block_db.gd` (all block pairs) and `test_m20_stabilization.gd`
      (ground face present, still present after station removal), and verified in
      `m20-table-ground.png`
- [x] **Item-ownership conservation**: deterministic split/merge/swap/quick-move,
      exact station→player shift-click and incompatible right-click regressions,
      a take-result-close-reopen check, 800 randomized inventory-panel operations
      and 600 randomized station transfers, plus real-scene integration coverage
- [x] **Persistence/cursor integrity**: a temporary cursor stack is not part of
      either `Inventory` model, so a save flushes it back first and a reload closes
      the inventory interface before applying (the second pass reproduced a reload
      that duplicated a held stack, 25 → 34 cobblestone). `flush_cursor()` on both
      panels plus `run_integration.gd::_persistence_cursor_section` and
      `test_m20_stabilization.gd::_test_cursor_flush` pin the invariant
- [x] Tests: unit **1569** / integration **357** assertions, exit 0, 0 bytes
      stderr; smoke world hash unchanged; `m20-inventory.png`,
      `m20-table.png`, `m20-furnace.png`, `m20-recipes.png` and
      `m20-table-ground.png` inspected
- [~] Human keyboard/mouse play-through of the new interfaces remains outstanding
- [ ] Dropped-item entity for a genuinely full inventory (mining overflow is
      still reported and lost) and a 2×2 hand-crafting grid

---

## M19 — Interactive crafting stations and persistent inventories

- [x] Targetable world objects: the existing E-key action uses the camera voxel
      ray and reach; aiming at a table/furnace shows an `E use …` prompt and the
      existing cell outline. Invalid/out-of-range targets report a message
- [x] Reusable station inventory model (`core/station_inventory.gd`): grid/input/
      fuel/output roles, item acceptance, stack caps, count-preserving insert/
      take/split/move/swap/deposit, `changed` notifications and atomic
      serialisation. Shared by every station kind instead of per-UI logic
- [x] Station behaviour (`core/station.gd`, `core/smelting.gd`): crafting table
      3×3 shaped/shapeless grid, live result preview and atomic `craft_grid()`;
      furnace timed smelting with data-driven fuel and cook times, output-full
      pause, input-change reset and persistent progress
- [x] Station registry (`core/station_registry.gd`): state keyed by world cell,
      lazily created, stale-state validation/pruning (loaded cells only), bounded
      furnace ticking near the player (64 blocks), chunk-unload survival
- [x] Dedicated interfaces (`game/station_panel.gd`, `game/station_slot.gd`): 3×3
      grid + result with ghost preview and Return grid/Take result for a table;
      input/fuel/output with COOK/FUEL bars and live status for a furnace; player
      row, carrying slot, tooltips, click/right-click/shift-click/drag & drop.
      Mutual exclusion with the C/I/O overlays; E/Esc closes; world input blocked
- [x] Persistence: save VERSION 6 adds `stations` rows (contents + furnace
      timers), validated before apply; v1–v5 load with no station state. Fixed a
      pre-existing F9 reload bug (`apply` received the unwrapped payload)
- [x] Destruction/replacement policy: contents transfer to the player (remainder
      reported if the inventory is full); placing a station clears stale state
- [x] Tests: `test_stations.gd` (unit) + 81 real-scene integration assertions;
      unit 1451 / integration 265 assertions, exit 0, 0 bytes stderr; smoke hash
      unchanged from M18; `m19-crafting-table.png` and `m19-furnace.png`
      inspected; `perf-look-m19.json` / `perf-settle-m19.json` show no frame-time
      regression (look p95 2.04 ms, settle p95 5.40 ms, radius 4, vsync off)
- [~] Human keyboard/mouse play-through of the new interfaces remains outstanding
- [ ] Station-adjacent conveniences not requested by M19 (shift-drag splitting
      across containers, dropped-item entities for full inventories)

---

## M18 — Visual quality upgrade

Design contract: `prototypes/m17/results/m18-visual-design.md`.

- [x] `--visual-test` reproducible showcase (clearing, material pads, terraces,
      pond, boulders/ores, stations, planted trees, fixed viewpoints), isolated
      from autosave/creatures/NPCs/raids
- [x] In-memory texture grading + near-white biome tints + grass top-only tint +
      per-cell variation + world-space macro-noise term
- [x] Baked vertex ambient occlusion with an optimized offset-table path
- [x] Custom crafting-table and furnace models (geometry inside the voxel cell,
      full-cube collision), with derived top/side/opening textures and a furnace
      ember glow carried in `UV2.y`
- [x] Rounded oak/pine crowns and denser leaf textures; deterministic boulder
      clusters with ore faces; runtime `WorldGen.plant_tree`
- [x] Custom sky shader (gradient, dawn/dusk band, sun/moon disc, clouds, stars),
      ACES tonemapping, four-split blended shadows, fog scatter/aerial perspective,
      retuned night palette
- [x] Water shader with depth absorption, wave normals, shoreline thinning and a
      flat source-water plane; reduced atlas checkerboard
- [x] `test_visuals.gd` regression module (1273 unit assertions total, 184
      integration assertions), perf harness rerun at radius 5
- [~] Live rotating-camera shimmer/video inspection and a human play-through
      remain outstanding
- [ ] Weather/particles, quality settings menu, richer bark/side material variants

---

## Phase A — Core playable world

- [x] Godot project that opens, runs and renders (4.7.2-stable, windowed run verified)
- [x] 16³ chunk storage, logical voxels authoritative, chunk↔world coordinate conversion with floor semantics
- [x] Central block definitions (35 blocks: terrain, ores, wood, glass, decoration, crafting
      table, furnace) + `core/item_db.gd` for the 26 non-block items (2026-10-19)
- [x] Face-culled chunk meshing, five render layers, no per-voxel engine objects
- [x] Deterministic terrain generation (seed 17017): height field, biomes, caves, ores, trees, decoration
- [x] Chunk streaming with per-frame generation/meshing budgets and neighbour-aware culling
- [x] Mesh construction runs on a dedicated worker thread (main thread only snapshots the
      voxel input and attaches finished meshes); profiling in the 2026-10-16 renderer
      investigation showed in-frame meshing was the frame-time spike source
- [x] First-person player: mouse look, WASD, jump, gravity, sprint, AABB collision
- [x] Block targeting (voxel DDA raycast), left-click break, right-click place against the targeted face
- [x] Placement blocked inside the player and inside other solids
- [x] Mesh + collision invalidation of the edited chunk and its neighbours
- [x] Water: logical fluid solver, cross-chunk propagation, bounded per-tick work, animated transparent surface
- [x] Texture atlas (Minetest `default` pack), directional sun with shadows, sky, fog, SSAO
- [x] Versioned save/load of block edits, fluid overrides, player and inventory (atomic write, corrupt-save quarantine)
- [x] Main menu, pause menu, autosave, HUD with hotbar and item counts
- [x] Automated test suite (1451 assertions, verified 2026-10-19) + runtime integration harness (265 assertions, verified 2026-10-19) + headless determinism fingerprint
- [x] Frame-time benchmark harness (`scripts/tests/run_perf.gd`): six scripted activities, per-frame
      timings and streaming counters, before/after JSON reports (verified 2026-10-16)
- [x] Capture harness for reproducible screenshots + objective image statistics tool
- [x] Visual quality pass: lighting/fog retuned and re-inspected; sand is bright and near-tree
      shadows are dark (both plausible, not fixed)

## Phase B — Building and survival

- [x] Inventory data model (27 storage slots + nine hotbar slots, item id + count +
      durability, serialisable); the hotbar is the only selectable region
- [x] Visible hotbar with real block icons, selection (1–9 and mouse wheel), counts and tooltip
- [x] Full inventory interface (M20, 2026-10-19) — `game/inventory_panel.gd` +
      `game/inventory_slot.gd` + `game/item_cursor.gd` + `game/ui_style.gd`, opened with I
      (or `--open-inventory`): a Minecraft-like 9×3 storage grid above the nine-slot hotbar,
      selected-slot highlight, counts, durability, tooltips, item facts, left/right-click
      pick/split/merge/swap, shift-click hotbar ↔ storage quick-move and drag & drop.  The
      permanent carrying slot is gone; a temporary cursor stack is drawn under the pointer
      and recovered on close.  Mutual exclusion with the crafting/settings/station panels;
      Escape closes it before pausing.  `m20-inventory.png` inspected
- [x] Collecting drops into the inventory (mining adds the drop; inventory-full feedback).
      The 36-slot model leaves 27 free slots after the starter kit, which fixes the reported
      iron/coal drops being refused by the old full nine-slot row; real-controller iron/coal
      mining is covered by integration tests
- [x] Placing items consumes them
- [x] Crafting recipes — `core/crafting.gd`: a **32-recipe, data-driven catalogue** in five
      categories (Basics, Building, Tools, Smelting, Food) with shaped *and* shapeless
      definitions, ingredient/output quantities, station requirements and a fuel cost.
      `craft`/`craft_many` are atomic across a batch; `missing`, `craftable_count` and
      `can_craft_times` back the interface; `match_grid` implements real shape semantics. A
      meta-test proves every recipe output is reachable from mining drops and other recipes
      (2026-10-19)
- [x] Crafting interface — `game/crafting_panel.gd`, opened with C: category filters, a
      scrollable list, output icons, have/need ingredient counts and per-row status.  **M20
      stabilization** makes the catalogue station-gated: a recipe is craftable in the
      catalogue only when its station (table/furnace) exists in the world and every
      ingredient/fuel/output check passes, otherwise the row names the missing station or
      item.  Hand, table and smelting rows all consume through the same atomic
      `Crafting` transaction as the world-object grids, so `m20-recipes.png` shows the
      furnace row ready with 8/8 cobblestone at a nearby table
- [x] Crafting stations: the recipe's `station` must exist **in the world**
      (`Crafting.best_station` scans loaded voxels within interaction reach); a furnace also
      serves table recipes, and smelting needs the furnace plus fuel. New `FURNACE` block id 34
      (2026-10-19). **M19** adds the world-object layer; **M20** rebuilds the panels over the
      full player inventory, makes grid cells take one ingredient per click/drag/shift-click,
      supports shaped mirroring, and fixes the old four-block station-detection radius that
      could hide table/furnace recipes. Tables/furnaces are targeted with E and keep their
      contents across close/save/chunk reload; the C-key catalogue is now station-gated over
      the same `Crafting` model
- [x] Items, tools, tool tiers and durability (2026-10-19) — new `core/item_db.gd` extends the
      id space with 26 non-block items (materials, food, 16 tools in four tiers) while keeping
      block ids unchanged; `Inventory` gained per-slot durability, `wear()` that clears broken
      tools, and a real per-slot stack cap of 64. Crafted tools work in gameplay: tiers set
      mining speed, durability is spent per block and per creature hit, and the HUD shows a
      durability bar plus `20 / 60` readout
- [x] Mining hardness and tool requirements (2026-10-19, revised) — holding the break action
      mines progressively (`ItemDB.break_seconds`, shown on a HUD progress bar); a block whose
      required tool class/tier is not held **refuses to break** (no progress, no removal, no
      durability spent) and the HUD names the requirement, so a gated resource can never be
      destroyed for no reward; ores
      drop lumps/crystals instead of ore blocks, and leaves/grass have deterministic chance
      drops (apple, wheat)
- [x] Hunger and survival settings (2026-10-19) — `Survival.hunger_step`/`starvation_damage`/
      `food_effect` plus fed `regen_step`: a 20-point bar, an exhaustion budget spent by
      idling/walking/sprinting, starvation damage that stops at a 1-health floor, and eating by
      right-click (a full body refuses rather than wasting the item, the golden apple heals
      too). HUD hunger bar; save VERSION 4 persists it. Longer/shorter food effects, saturation
      and food poisoning are not implemented
- [x] Environmental feedback (hurt flash, bounded reversible camera shake; particles not included)
- [x] Death and respawn (death screen and valid spawn; no creature combat in this increment)
- [x] Configuration screen (render distance, sensitivity, vsync) — `core/game_settings.gd`
      (clamped, validated, dictionary round-trip) + `game/settings_panel.gd`, opened with `O`
      or `--open-settings`; render distance applies live through
      `ChunkStreamer.apply_render_radius`, sensitivity to the player, vsync to the display,
      all persisted to `user://voxelworld_settings.cfg` (CLI `--render-distance` still wins for
      captures). `test_settings.gd` + 8 integration assertions; `settings-ui.png` inspected
      (2026-10-18)
- [x] Pause menu

## Phase C — Living world

- [x] Day/night cycle (sun angle, sky, ambient and fog follow a clock) — `day_night.gd`,
      tested, `day-noon.png` / `day-dusk.png` / `day-night.png` inspected;
      `--time=` / `--time-rate=` drive it, saved with the world (save VERSION 2).
      **Finished and fully visually verified 2026-10-18**: the whole clock was captured and
      inspected (`day-cycle-000/025/050/055/075/095.png`), the missing mid-twilight frame is
      included, image statistics confirm the monotonic bounded curve, the HUD clock text
      matches, and a live `--time-rate=120` run advanced the clock in PLAYING. The quick
      sunset→night transition is a tuning choice (the curve is pinned by tests), not a defect.
- [x] One passive boar species (bounded deterministic nearby spawn, unique per-column
      identity, cap 6, 54-block despawn range, bounded pruning, voxel-aware wandering,
      primitive animated silhouette, player damage and species-specific loot —
      **M21** replaced the old hard-coded Oak Log with meat/hide/bone; unit + runtime
      integration verified 2026-10-19). Ground is taken from the **live world voxels**
      (`supports_standing` / `wander_destination` in `core/passive_creatures.gd`), not the
      procedural generator, so mining the ground block removes the spawn/move site
      (reviewer defect fixed 2026-10-16 with new unit assertions)
- [x] Hostile creatures (targeting, melee, spawning in the dark) — `core/hostile_creatures.gd`
      + `game/hostile_creature.gd`: one "grunt" species, night-only gate (or `--spawn-hostiles`),
      live-ground spawn 12-32 blocks from the player (cap 4), chase that stops at attack range
      and refuses mined/flooded floor, contact melee (2 damage / 1.2 s), 4 HP, bones + a chance
      of coal (M21 `CreatureDB` loot), bounded pruning, transient (not saved). `test_hostiles.gd` and 8 real-scene
      integration assertions; `hostile-creature.png` inspected (grunt at midnight, "Grunt hurt
      (3/4)"). Verified 2026-10-18
- [x] Combat, damage exchange and loot (minimal melee exchange, 2026-10-18) — the player's LMB
      creature path damages hostiles and kills them for one drop; a hostile in contact damages
      the player through the shared impact-damage path (invulnerability window + camera shake),
      verified in integration (20→18 health, four hits to kill, loot added). Weapons/durability,
      ranged attacks and varied loot remain out of scope
- [x] Passive creature spawning/despawning tied to the player's surroundings (38-block
      spawn search, 54-block retention, streamed loaded-cell checks, deterministic IDs,
      live-world ground/headroom so player edits are respected)
- [x] Creature save policy documented: transient living animals are re-seeded from the
      world seed and current player neighborhood on load; dead-creature drops are placed
      directly in the existing persistent inventory. Save format remains VERSION 3.
- [ ] Weather or environmental variation
- [x] Exploration incentives (2026-10-19): ores now feed real progression — coal fuels the
      furnace, iron ore (needs a stone pickaxe) smelts into ingots for iron tools, gold lumps
      make the golden apple and diamond ore (needs an iron pickaxe) makes the top tool tier.
      The reward for caving is a strictly better tool chain, and `test_crafting.gd` proves
      every recipe is reachable from mining alone

## Phase D — Structures and settlements

- [x] Procedural structures (camps, ruins, wells) as reusable definitions (2026-10-19) —
      `core/structure_db.gd` + placement in `world_gen.gd`: five kinds (Abandoned Hut with
      stations inside, Campsite, Ruined Watchtower, Desert Well with water, Ore Outcrop), one
      per 96-block region at a deterministic hash-chosen anchor, biome/slope/sea-level siting,
      written across chunk boundaries so generation order and threading stay irrelevant.
      `--find-structure=<id|any>` diagnostic; `structure-hut.png` / `structure-tower.png`
      inspected; `test_structures.gd` (43 assertions) pins definitions, determinism, siting,
      cross-chunk completeness and bedrock preservation
- [x] Reusable structure definition format (2026-10-19) — ASCII layer maps with a per-layer
      symbol key, `.` = leave the world alone, `_` = force air, negative `dy` for dug features,
      validated by `StructureDB.validate()` (reserved symbols, unknown blocks/biomes, footprint
      limit, siting limits). Pure data: the generator, tests and a future editor share it
- [ ] Player construction beyond single blocks (blueprint/paste helpers)
- [x] NPC foundation with persistent identity and state (2026-10-19) — `core/npc.gd` (a resident
      is a serialisable dictionary: id, name, role, task, position, home, target, carried,
      health) + `core/settlement.gd` (settlements derived from placed huts/campsites), saved as
      save VERSION 5 and restored by `_apply_npcs`. Same world, same residents: identity,
      roster and roles are pure functions of the seed
- [x] NPC movement and basic tasks (2026-10-19) — the `SEEK → WALK → WORK → RETURN` loop: a
      woodcutter fells exposed nearby logs and a miner works exposed stone/ore within 10 blocks
      of home, then carries the load back and hands it to the settlement store. Bounded to
      loaded chunks, exposed blocks, the gather radius, a search budget and vertical reach;
      `game/npc_node.gd` walks the terrain with physics, and the game pulls a fallen resident
      home. Guards, construction, farming and trading are not implemented
- [x] Settlement layout and resident assignment (2026-10-19) — a settlement *is* its structure's
      footprint, and it is assigned 1-3 residents with deterministic names and roles. There is no
      plot/building layout generation and residents do not build
- [x] Resource storage and task delegation (2026-10-19) — each settlement has a shared store that
      residents deliver to (persisted, with lifetime counters per resident). **M21** adds a
      player-craftable 27-slot storage chest with the same persistent station inventory; the
      settlement store itself is still not player-accessible and there is no trading
- [x] Defensive behaviour and enemy raids (2026-10-19) — `core/raid.gd` schedules a raid every
      other night with a deterministic group size and spawn ring; the raiders are the existing
      grunt node aimed at a resident (retargeting the next resident, then the player), and
      residents defend with the new `Task.DEFEND` (walk at the nearest raider inside
      `DEFEND_RADIUS`, strike every 1.4 s for 2 damage, back to work afterwards). The game
      starts/ends the raid, routes damage both ways and reports the outcome; `--raid-now` forces
      one for captures. `raid-night.png` inspected. Limitations: raids only happen near the
      player, residents have no weapons/armour, raiders do not break blocks, a settlement's dead
      are not replaced, and "already raided tonight" is not saved
- [ ] City-management foundation

---

## Engineering backlog (not gameplay)

- [x] Stale padded-buffer bug in `ChunkMesher._fill_padded` (leaked the previous chunk's
      neighbour data into a reused buffer) — fixed, regression test added
- [x] Inverted triangle winding in `ChunkMesher` (faces wound opposite to Godot's
      front-face convention, so `cull_back` hid the terrain and the collision trimesh
      reported inverted normals — the root cause of the reported WASD movement failure and
      the rendering defects) — fixed in `chunk_mesher.gd` + legacy `main.gd`, pinned by the
      `test_mesh_winding.gd` unit test and the `run_integration.gd` runtime test
- [x] Determinism regression tests (streaming batch sizes, generation order, fingerprints)
- [x] Persistence regression test (`SaveManager` write/read/apply round-trip, version-1
      load, seed-mismatch rejection, corrupt-save quarantine) — previously untested
- [x] Clay was unreachable: the `elif underwater and world_y >= height - 2` clay clause in
      `world_gen.gd` was shadowed by the preceding `>= height - 3` branch, so clay never
      generated (and the `4 Clay → 1 Brick` recipe was unusable). Reordered so the clay band
      generates in submerged columns; `test_generation.gd` asserts clay is present.
      This changed world content — `world_hash` is now `441363152919021799`
      (`faces`/`faces_hash` unchanged: clay swaps one opaque subsurface block for another).
- [x] Texture array layer sampling: every voxel shader sampled `texture(atlas, vec3(UV, UV2.x + 0.5))`.
      The `+ 0.5` puts the array-layer coordinate exactly on the midpoint between two layers;
      this engine build rounds the coordinate, so faces and per-pixel patches rendered the
      neighbouring texture (grass_top→gravel, sand→sandstone, leaves→log side) and the pattern
      changed with the camera. Fixed by sampling the exact integer layer in all five shaders;
      pinned by a shader-source contract test in `test_textures.gd` and before/after captures.
- [x] Streaming frame-time spikes: attribution showed every >20 ms frame did chunk generation
      and/or meshing on the main thread (gen+mesh frames averaged 23–25 ms, worst 52 ms; idle
      frames cost ~1.2 ms). Chunk meshing moved to a worker thread (`capture_input` snapshot on
      the main thread, pure `build_geometry` on the worker, `assemble` + node attach on the main
      thread); measured walk p99 28.5→16.3 ms, 1 % low 31.9→53.5 fps, and settling 4.3→3.1 s
      wall clock. See the renderer-investigation section of `godot-progress.md`.
      **Chunk generation followed on 2026-10-18** (second worker thread, own `WorldGen`):
      settle p99 22.2→8.3 ms, walk p99 16.3→6.3 ms, 1 % low 52.4→111.2 fps, world-ready
      5.3→3.5 s. Reports `perf-{walk,settle}-{inline,bg}.json`.
- [~] First-fill cost: after background generation the world is ready in ~3.5 s wall clock
      (was ~5.3 s) for 392 chunks at radius 4; the first-PLAYING frame (~53 ms, engine
      first-use) is unchanged and present in every baseline. Generation and meshing are both
      off the main thread now; the residual per-frame streaming cost is geometry **attach**
      (ArrayMesh upload + trimesh shape, up to ~26 ms on one settle frame)
- [x] Background/threaded generation (mission §9, 2026-10-18): chunk generation was the last
      streaming step inside the frame (~6 ms/chunk typical, up to ~21 ms). It now runs on a
      second worker thread that owns its own `WorldGen`; the main thread only submits
      coordinates and adopts finished chunks, bounded by `max_generation_in_flight`.
      A/B on one machine (seed 17017, radius 4, vsync off): settle p99 22.2 → 8.3 ms,
      walk p99 16.3 → 6.3 ms, walk 1 % low 52.4 → 111.2 fps, world-ready 5.3 → 3.5 s.
      Tested by `test_streaming_lifecycle.gd` (in-flight cap, stale results dropped, clean
      `clear()`/restart) and the `test_determinism.gd` background-vs-inline equivalence.
      Remaining hitch is the first-PLAYING frame (~53 ms) and GPU-bound frames, not
      generation; see the progress report
- [x] Benchmark harness measured the display refresh rate, not the game (2026-10-18): the
      settings screen persists vsync and `game.gd::_ready()` applies it, overriding the
      harness's pre-boot `VSYNC_DISABLED`. `run_perf.gd` now re-asserts vsync-off/max-fps
      after boot and before each phase, records `vsync_mode`/`max_fps`/`threaded_*` in the
      report, and gained `--sync-generation` for single-machine A/B runs
- [x] Save format versioning: VERSION 4 accepts versions 1..4 (adds hunger; v1-v3 fields remain
      optional); unknown versions are still quarantined
- [x] Inventory payload validation was not atomic (2026-10-19): `Inventory.from_dictionary`
      wrote entries as it validated them, so a malformed save could half-apply the hotbar, and
      `SaveManager.apply` mutated the world before it noticed. Both now validate into scratch
      storage first and reject the payload before any live state changes; `durability` rides in
      the same dictionary with no format break
- [x] Dead `BlockDB.placeable` array removed (2026-10-19): placement is now decided by
      `ItemDB.is_block()`/`placeable_block()`, which knows about non-block items
- [x] Remove temporary diagnostics (`M17_OPTIONS`, `_probe_surface.gd`)
- [x] Passive creatures decided ground from the procedural generator (`height_at` /
      `_surface_block`) instead of the live world, so a mined ground block still looked
      like valid floor and a boar could spawn/wander over a hole. Fixed with the node-free
      `supports_standing` / `wander_destination` helpers in `core/passive_creatures.gd`
      (loaded + solid + non-liquid ground; loaded-air foot/head) used by both
      `spawn_candidates` and `game/passive_creature.gd::_physics_process`; regression
      assertions added to `test_creatures.gd` (reviewer defect, 2026-10-16)
- [x] Chunk-boundary invalidation along Z was inverted: `voxel_world.gd::_flag_neighbours`
      mapped the `-Z` border to `BACK` (+Z) and the `+Z` border to `FORWARD` (-Z), so a block
      broken on a chunk's Z border never dirtied the real neighbour. Its shared face stayed
      culled in the render mesh and collision, letting the player see through the hole and walk
      through the boundary wall (X/Y were correct, making it look intermittent). Fixed with
      explicit `(0,0,-1)` / `(0,0,1)` offsets; pinned by the new `test_edit_rebuild.gd`
      (all six boundary directions, the threaded streamer, and consecutive edits racing a
      rebuild) and 17 new real-scene integration assertions (mesh + collision + physics-ray
      probes). Before/after windowed captures `m17-edit-{bug,fix}-after.png` (2026-10-18)
- [x] Asynchronous chunk-rebuild race (2026-10-18): a mesh build in flight for a chunk whose
      neighbour set changed (unload/load/regeneration) was attached with the old border because
      the neighbour change only queued the chunk and did not bump its `mesh_revision`; the stale
      result then cleared the dirty flag and the queued rebuild was dropped, leaving a
      render+collision hole at the edge of the loaded region. `chunk_streamer.gd` now
      `mark_dirty()`s loaded neighbours on chunk create/remove and keeps a still-dirty coordinate
      queued in `_collect_mesh_batch`. Pinned by
      `test_edit_rebuild.gd::_test_pending_build_survives_neighbour_unload` (RED: 3 failures,
      GREEN: pass)
- [x] Player kept moving while paused (2026-10-18): `_pause()` disabled interaction but not
      physics, so WASD and gravity ran behind the pause menu (30 frames moved the body 8.67
      units). `_pause()`/`_resume()` now toggle `player.set_physics_process(...)`; integration
      asserts no movement while paused (0.000 units). This was the reproducible WASD reliability
      defect
- [x] Test runner hung on a module that fails to parse (2026-10-18):
      `(script as GDScript).new()` aborted `_run_all` and left the suite running until the 300 s
      watchdog. `run_tests.gd` now checks `can_instantiate()` and reports a normal failure
- [x] Remaining streaming hitch (2026-10-18): generation moved off the main thread
      (`threaded_generation`). In-frame generation no longer exists, so the frames that used to
      cost 23-26 ms doing it are gone (settle p99 22.2→8.3 ms, walk p99 16.3→6.3 ms on the A/B
      above). What remains is the first-PLAYING frame (engine first-use, ~53 ms, present in
      every baseline) and occasional GPU-bound frames with 6.5 ms of CPU work; geometry attach
      (ArrayMesh + trimesh shape) is the largest surviving main-thread streaming cost
