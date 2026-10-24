# M41c - First-Person Hand and Tool Visual Polish

Status: **COMPLETE** as a focused visual-quality pass, with the limitations
listed at the end. Automated suites pass and the result was inspected in real
runtime captures. No commit was made.

Canonical project: `C:\Users\Admin\Documents\Projects\VoxelWorld_Godot`.
Engine: Godot `4.7.2.stable.mono.official.ed1daf0bf`.

## Reference note

The supplied reference image was present in the task description but was
removed from the working context before this session could inspect it, and it is
not stored in the repository. The implementation therefore targets the
milestone's detailed written design characteristics (strong silhouette, layered
metal, shaped wooden haft, material separation, deliberate bindings, a coherent
tool set, gameplay readability) and the existing arena/character style. No claim
is made that the rendered result was compared pixel-for-pixel with the missing
reference. This is the main limitation of this pass.

## 1. Root cause of the original visual weakness

The M41b models were not crude because they had no detail. They had detail on
the wrong side of the model:

- **The camera-facing layers were on the far side.** The pickaxe face plates,
  central boss, rivets, axe face, shovel face, sword face and edge highlights
  were authored at negative local Z. The item is in front of the first-person
  camera, so the camera sees its **+Z** side. The rendered result therefore
  showed only the dark body shells; every lighter layer was hidden behind them.
  This is why the M41b pickaxe read as a flat brown stick with a thin edge,
  despite the layered code.
- **The wooden tier used almost the same brown for head and haft.** The head's
  metal colour was `(0.50, 0.33, 0.14)` and the handle was `(0.29, 0.18, 0.09)`.
  Under the warm arena sun the head and handle merged into one tan silhouette.
- **The pickaxe head was too small and too thin.** Its total width was 0.70 model
  units (about 0.29 m) and its profile was only 0.08 units tall. At gameplay
  distance it read as a narrow crescent/scythe, not a stout pick head. The
  enlarged head only exists in the M41c profiles.
- **The fist was built in arm space, not in the tool frame.** The hand was a box
  with four vertical finger strips; the haft passed behind the palm. The fingers
  did not close around the handle, the handle appeared to emerge from the top of
  a mitten, and the pale sleeve was louder than the hand.
- **The first-person composition was barely inside the lower-right quadrant.**
  The enlarged design initially crossed the reticle centreline. The fix had to
  preserve the strict `reticle_clear()` contract rather than move the reticle.
- **The axe and shovel were broad flat plates.** Their only depth cues were
  hidden on the far side, so they read as uniform grey/blue slabs.

## 2. What changed

### Held tool construction (`godot/scripts/game/held_item_visual.gd`)

- Replaced the three single-colour box silhouettes with a consistent **three-
  layer metal construction**: dark faceted body, lighter inset face, bright
  cutting edge. The pickaxe also gets a lighter top bevel on both arms.
- Moved every visible layer, boss and rivet to the **camera-facing +Z side**.
- Rewrote concave profile extrusion to use `Geometry2D.triangulate_polygon`, so
  the bearded axe and pick underside cannot produce overlapping/fanned faces.
- Gave mirrored and grouped parts **unique names** (`PickArmL`, `PickArmR`,
  `PickRivetL`, ...) instead of relying on Godot's silent auto-renaming. This
  makes the model inspectable and the tests meaningful.
- **Pickaxe:** broad two-armed head (0.984 model units wide), heavy central eye
  with a domed ring boss and four corner rivets, layered faces, bright tips,
  shoulder bolsters, a leather binding and a metal socket. The head is now the
  dominant silhouette, not a thin blade.
- **Axe:** tall bearded blade with a flared top horn, a concave lower beard
  notch, an inset cheek plate, a bright curved edge, a visible poll face, eye
  bands, a top lug, rivets and a leather binding.
- **Shovel:** broad shaped spade with a rolled bright lip, a recessed darker
  scoop panel, a raised centre spine, shoulder edges, a step, a socket and two
  reinforcing rivets.
- **Sword:** longer layered blade with a lighter face, raised centre ridge,
  bright edge strips on both sides, a brass blade collar, a brass guard with
  quillon studs, a gem inset, a pommel boss and a leather wrapped grip.
- **Hafts:** each long tool now has four tapered shaft sections with different
  widths/tones, raised grain strips, a leather grip sleeve with five raised
  wraps and two metal collars, a metal butt cap with a rivet, a head-side
  ferrule and a second leather binding. This is a deliberate segmented haft, not
  a uniform rectangular stick.
- **Palette:** all tiers now read as forged metal heads with a warm wooden haft.
  The wooden tier is a dark warm steel rather than raw brown wood, so the head
  remains legible against the handle. Stone is a cool grey, iron a brighter
  steel, diamond a restrained teal.
- Restrained metallic response and a small emission term (6.5% of albedo) keep
  the tool readable under the pavilion roof and canopy without making it glow.

### Fist and first-person presentation (`godot/scripts/game/first_person_arms.gd`)

- The fist is now built in the **held item's local frame** (`GripHand`). The
  palm closes behind the haft, four finger wraps cross the front, side knuckles
  and dark creases separate the fingers, and a three-segment thumb closes the
  grip diagonally. The wrist has a leather strap.
- The grip origin is inside the palm and the haft passes through it; there is no
  floating handle or gap in the captured frames.
- The arm was moved right and slightly up so the fist remains visible beside the
  hotbar instead of being covered by it.
- The sleeve was muted from near-white to a tan cream so it no longer outshines
  the hand and tool.
- Swing animation, walk bob, look sway, jump lift and the existing camera/arm
  pivot are unchanged. The tool still follows the arm as one assembly.

### Per-item presentation (`godot/scripts/game/item_presentation.gd`)

- Added item-appropriate first-person holds. The pickaxe now leans diagonally
  (32° roll) with the head swept to the lower right; the axe, shovel and sword
  have their own scales and angles.
- Long-handled tools are gripped slightly up the haft. This keeps the larger
  head below the reticle and makes the held tool read as a carried tool rather
  than a display prop.
- The third-person rotations and scales were **not changed**.

### Evidence tooling

- `scripts/tests/run_m41c_demo.gd` boots the real game and captures the five
  required pickaxe states plus the axe, axe swing, shovel, sword and a
  third-person frame.
- `scripts/tests/run_tool_preview.gd` renders the four tools on a neutral studio
  background for construction inspection only. It is not used as gameplay
  evidence.
- `scripts/tests/test_tool_visuals.gd` is a new visual contract module covering
  layered construction, material count, grip containment, per-tool screen
  bounds, reticle clearance and swing clearance.

## 3. Assets inspected and decision

The full source/licence table is in
[`m41c-asset-review.md`](m41c-asset-review.md). Summary:

- **Quaternius Cube World Kit** (`https://quaternius.com/packs/cubeworldkit.html`,
  CC0, 108 models, FBX/OBJ/Blend/glTF): closest external style, but the tool
  props shown in the official preview are simple flat T-shapes with less detail
  than the target. Kept as a **reference/future NPC-prop source**, not imported.
- **Kenney Voxel Kit** (`https://kenney.nl/assets/voxel-kit`, CC0, 48 files, 3D):
  downloaded to a temporary folder and extracted. It contains 47 `block N`
  cubes plus a base block, one material and no tools or hands. **Not usable for
  held tools.**
- **Kenney Voxel Pack** (`https://kenney.nl/assets/voxel-pack`, CC0, 2D,
  128 x 128): 2D icons only. **Not a 3D source.**
- **KayKit Adventurers / Quaternius Modular Weapons**: high individual quality
  but smooth low-poly surfaces that clash with the voxel world. **Not
  integrated.**
- **Phantom Camera** (MIT): not needed; the camera rig is preserved.
- No external model, texture, animation or plugin was added. The game still has
  no external runtime art dependency beyond the existing in-repo textures.

## 4. Files changed

Game code:

- `godot/scripts/game/held_item_visual.gd`
- `godot/scripts/game/first_person_arms.gd`
- `godot/scripts/game/item_presentation.gd`
- `godot/scripts/tests/run_tests.gd` (registers the new visual module)

New tests and evidence tooling:

- `godot/scripts/tests/test_tool_visuals.gd`
- `godot/scripts/tests/run_m41c_demo.gd`
- `godot/scripts/tests/run_tool_preview.gd`

Documentation/evidence:

- `prototypes/m17/results/godot/m41c-report.md`
- `prototypes/m17/results/godot/m41c-asset-review.md`
- `prototypes/m17/results/godot/m41c-before-after.png`
- `prototypes/m17/results/godot/m41c-grip-closeup.png`
- `prototypes/m17/results/godot/m41c-states.png`
- `prototypes/m17/results/godot/m41c-demo-00.png` ... `m41c-demo-10.png`
- `prototypes/m17/results/godot/m41c-demo-manifest.json`
- `prototypes/m17/results/godot/m41c-model-lineup.png`
- `prototypes/m17/results/godot/m41c-model-pickaxe.png`
- `MILESTONES.md`, `PROJECT_STATUS.md`, `godot/ASSET_MANIFEST.md`,
  `prototypes/m17/README.md`

No item IDs, recipes, save data, inventory rules, tool tiers, damage, mining,
placement, camera or character code were changed.

## 5. Before/after runtime evidence

All gameplay images are offscreen viewport captures from the running Godot
game, not mockups or a generated promotional image. The composite and crops are
made from those exact frames; no content was painted or synthesised.

| Image | Contents |
| --- | --- |
| `m41c-before-after.png` | M41b vs M41c first-person pickaxe, full frames. |
| `m41c-grip-closeup.png` | The same frames cropped around the fist and haft. |
| `m41c-states.png` | Idle, nearby block, walking, mining swing, pavilion shade and an axe swing. |
| `m41c-demo-00.png` | Pickaxe idle, clear area. |
| `m41c-demo-01.png` | Pickaxe facing a nearby staged block. |
| `m41c-demo-02.png` | Pickaxe while walking. |
| `m41c-demo-03.png` | Pickaxe at the mining-swing peak. |
| `m41c-demo-04.png` | Pickaxe under the pavilion roof (shade). |
| `m41c-demo-05.png` | Stone axe, first person. |
| `m41c-demo-06.png` | Stone axe swing. |
| `m41c-demo-07.png` | Iron shovel, first person. |
| `m41c-demo-08.png` | Diamond sword, first person. |
| `m41c-demo-09.png` | Pickaxe during a first-person jump. |
| `m41c-demo-10.png` | Third-person pickaxe with the preserved 3.8 m / 0.70 m rig. |
| `m41c-model-lineup.png` | Supplementary model inspection (not gameplay). |
| `m41c-model-pickaxe.png` | Supplementary three-quarter pickaxe inspection. |

Measured first-person footprint from the real `screen_bounds()` and
`reticle_clear()` calls in the capture manifest:

| Frame | Reticle clear | Visible width | Visible height |
| --- | --- | --- | --- |
| Pickaxe idle | yes | 38.3% | 45.1% |
| Pickaxe walking | yes | 38.6% | 45.0% |
| Pickaxe swing | yes | 37.4% | 41.0% |
| Pickaxe jump | yes | 38.3% | 43.6% |
| Stone axe | yes | 35.2% | 43.6% |
| Iron shovel | yes | 34.5% | 45.0% |
| Diamond sword | yes | 37.1% | 44.6% |

The idle pickaxe's highest point is at local `y = -0.0559` (below the `-0.05`
reticle-clearance threshold); during the jump it is `-0.0750`. Its visible
bounds begin at screen `x = 790`, `y = 395` in a 1280 x 720 frame, and it stays
entirely in the lower-right quadrant in every first-person state.

## 6. Validation

Commands were run from the repository root with the recorded Godot 4.7.2
executable,
`C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe`.
The table abbreviates it as `godot`.

| Suite | Command | Result | Exit |
| --- | --- | --- | --- |
| Unit | `godot --headless --path godot --script res://scripts/tests/run_tests.gd` | `M17_TESTS_PASS 3605 assertions` | 0 |
| Integration | `godot --headless --path godot --script res://scripts/tests/run_integration.gd -- --straight-to-game` | `M17_INTEGRATION_PASS 621 assertions` | 0 |
| Regression | `godot --headless --path godot --script res://scripts/regression.gd` | `M17_REGRESSION_PASS assertions=52` | 0 |
| Runtime captures | `godot --path godot --script res://scripts/tests/run_m41c_demo.gd` | `M41C_DEMO_DONE frames=11` | 0 |
| Model inspection | `godot --path godot --script res://scripts/tests/run_tool_preview.gd` | two PNGs written | 0 |

The unit run's stderr contains one intentional `ERROR: Parse JSON failed` from
`test_m26_protection.gd`, which deliberately feeds `SaveManager` a corrupt save
and asserts rejection/quarantine. The process exit code is still 0 and the suite
reports pass. Integration and regression stderr were empty.

The M41b baseline was 3497 unit assertions; the new visual module adds 108
assertions. No existing threshold was relaxed. The existing
`test_player_visuals.gd` checks for the first-person arm's lower-right entry,
reticle clearance, sword width and swing clearance still pass unchanged.

### What was directly verified

- All four tools were inspected in the running viewport at 1280 x 720.
- The five required pickaxe states (idle, nearby block, walking, swing, shade)
  were captured and inspected as pixels, not inferred from a manifest. A jump
  frame confirms the grip stays intact while airborne.
- The grip was inspected in a zoomed crop: the haft enters the fist, the finger
  wraps and thumb are present, and the wrist/bracer/sleeve connect.
- The manifest proves reticle clearance and the lower-right footprint for every
  captured tool.
- The third-person capture shows the same shared tool model in the character's
  hand.
- The automated suites above pass with the recorded assertion counts.

## 7. Preserved behaviour and third-person camera

The following were not changed in this pass:

- `VoxelPlayer` camera modes, shoulder offset, camera distance, collision
  sweeps, eye-origin aiming and crosshair convergence.
- Placement preview/placement transaction, mining progress, attack and swing
  semantics.
- Item IDs, tiers, recipes, durability, inventory, hotbar, save data and world
  generation.
- The third-person camera remains the M41b rig: 3.8 m default distance, 0.70 m
  side offset, two-stage collision collapse, body hidden below 1.35 m. The only
  third-person-visible change is the shared held-tool model, which is more
  detailed than before. `m41c-demo-10.png` is a third-person capture with that
  unchanged rig.

## 8. Remaining limitations

- **The reference image was not available for this session.** The result follows
  the written design language and the game's established style; a direct
  silhouette comparison against the supplied image remains unverified.
- **The hand is still a box-built voxel fist**, not a skeletal rig. It has a
  palm, four finger wraps, side knuckles, creases, a three-part thumb and a
  wrist strap, but no per-joint animation. A close inspection at 1.5x still
  shows blocky finger geometry.
- **The visible haft between the fist and the head is shorter than a real
  pickaxe's.** Keeping the enlarged head below the reticle and above the hotbar
  required gripping higher on the haft. The tool reads correctly in the
  lower-right, but this is a composition compromise, not a physically exact
  two-handed grip.
- **The axe, shovel and sword are stylised in-house interpretations.** The sword
  has no reference counterpart. They are consistent with the pickaxe's material
  and construction language but are not production DCC assets.
- **No human mouse/keyboard play session was run.** Evidence is from the running
  game's offscreen viewport and the scripted demo. Input paths are covered by
  the existing integration suite, but a human visual playtest was not performed.
- **No external pack was integrated**, so there is no runtime side-by-side
  comparison against Quaternius or Kenney. That is intentional: none matched the
  target better than the in-house geometry.
- **Shields remain unsupported.** There is no shield item in `ItemDB`, so none
  was fabricated.
- No commit was made. The pre-existing uncommitted M41/M41b work was preserved.
