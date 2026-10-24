# M41b - First-Person Tools and Third-Person Framing (Visual Correction)

Status: **COMPLETE** as a visual correction pass, with the limitations listed at
the end. The original M41 implementation passed its tests but failed visual
acceptance; this pass rebuilt the presentation rather than adding more tests to
the old look.

## What was wrong

The M41 captures showed four concrete defects:

- The first-person arm entered the camera at a steep pitch and read as a large
  pale slab. The hand and tool were close to the near plane, so a 0.11 m forearm
  projected to several hundred pixels.
- The wooden pickaxe used almost the same brown for its handle and head, and the
  tool sat over the centre-right of the frame instead of the lower right. The
  axe and shovel were broad, uniformly lit polygons that clipped to white.
- The third-person character sat almost under the crosshair, on a featureless
  white pad. The held item was often hidden by the arm/body, and a tight camera
  collision could put the camera inside the character's head.
- The shared character had no rear-view detail and the tool grips were offsets
  rather than a coherent hand/item arrangement.

## What changed

### First-person tools and hand

- Added `scripts/game/item_presentation.gd`: one reusable profile for per-item
  size, grip offset, first-person rotation and third-person rotation. Neither
  camera owns scattered per-item offsets now.
- Rewrote `scripts/game/held_item_visual.gd`:
  - bevelled box geometry (twelve chamfered edges, flat faceted normals);
  - extruded polygon profiles for pick tips, axe blades, shovel scoops and sword
    blades, so each tool has a deliberate silhouette;
  - per-tier palettes with separate dark metal, body metal, edge highlight and
    rivet tones; dark walnut handles, leather grip wraps, collars and pommels;
  - a brass sword guard and pommel inset, a fuller and blade-edge strips;
  - restrained metallic response (`metallic` weights are scaled down) so the
    broad blade faces do not clip to white under the outdoor sun.
- Rewrote `scripts/game/first_person_arms.gd`:
  - the shoulder pivot is off-screen at the lower right and the forearm enters
    from the bottom edge; the hand is at a natural distance from the eye;
  - the tool origin is the grip, so the handle passes into the fist instead of
    being drawn over the knuckles;
  - the hand has a wrist, palm, knuckles, three finger blocks and a thumb;
  - walk bob, look sway and swing amplitude are much smaller; the tool stays
    below the reticle at rest and through the swing.
- The first-person assembly is now roughly 25-30% of the frame width instead of
  the old slab that covered the centre.

### Third-person framing

- `VoxelPlayer` now defaults to a 3.8 m camera distance and a 0.70 m
  over-the-shoulder offset. The body sits clearly left of the screen-centre
  crosshair (unit test checks the projected head position).
- The camera collision is two-stage: it first collapses the shoulder offset when
  a wall is beside the player, then collapses the distance along the view axis.
  This avoids the old failure where a wall next to the shoulder origin reported a
  0.18 m distance and pushed the camera into the character.
- The body is hidden below 1.35 m of camera distance; a tight wall now produces a
  clean first-person-like view instead of a screen-filling head. The body returns
  when the camera has room.
- Aiming remains unchanged in principle: the target ray still starts at the
  player's eye and converges on the crosshair. The placement preview and
  `place_selected()` still consume the same `placement_preview()` result.
- Settings exposes the persisted **Camera side offset** alongside view and
  distance. The setting is clamped to 0.0-1.0 m.

### Character and held item

- `PlayerCharacter` gained a framed backpack with a flap, shoulder straps and
  buckles, a bedroll, side pouches, a shaped tunic hem, a collar, belt and
  buckle, layered hair, ears, nose, eyes/brows/mouth, sleeve cuffs, bare hands
  and boot soles.
- The right arm hangs slightly away from the torso so the held tool clears the
  body in the rear view. The held item follows the arm's walk and swing poses.
- The third-person tool scale is larger than the first-person scale so the item
  reads at four metres, while the first-person scale is restrained.

## Validation

Godot 4.7.2, canonical project `godot/`.

- Unit suite: `M17_TESTS_PASS 3497 assertions`.
- Integration suite: `M17_INTEGRATION_PASS 621 assertions`.
- Regression: `M17_REGRESSION_PASS assertions=52`.

New unit checks include:

- the first-person arm occupies less than 42% of the frame width and less than
  55% of the frame height, enters from the lower right and clears the reticle;
- the detailed sword has more than ten silhouette/material parts, still reports
  the real item id and stays in the right half of the frame;
- the third-person camera focus projects to the screen centre while the
  character's head projects clearly left of centre;
- the aim direction still points from the eye to the crosshair focus;
- the settings model round-trips the shoulder offset.

New integration checks include the Settings shoulder control applying live. The
existing wall-collision, third-person placement, mining, creature targeting and
menu tests all still pass.

## Before/after assessment

`m41b-before-after.png` is the direct comparison.

Visibly improved:

- The first-person arm no longer dominates the view. The old pale slab is gone;
  the hand and forearm enter from the lower right and the tool is a held prop.
- The pickaxe, axe, shovel and sword now have distinct silhouettes, material
  separation, bevels, handles, grips and highlights. The old wood pickaxe's head
  no longer disappears into the arm colour.
- The third-person character is clearly left of the crosshair, has a readable
  rear-view silhouette (backpack, bedroll, straps, pouches) and holds the selected
  tool in the right hand.
- A wall/terrain collision no longer turns the character into a giant head.
- The camera and tool remain stable while looking, walking, jumping and swinging.

Remaining incomplete or limited:

- The shield requirement cannot be demonstrated because VoxelWorld's `ItemDB`
  has no shield item. No fake shield was added.
- The hands are still box-built; they are not a skeletal hand rig and do not have
  per-finger animation.
- The axe and shovel are stylised, readable props, not production DCC assets. The
  shovel in particular reads as a broad spade rather than a thin real-world
  shovel.
- The external asset review recommends no integration for this pass. See
  `m41b-external-asset-review.md`.
- The reference concept image is not stored in the repository; the visual
  assessment used the written acceptance criteria and the running-game captures.
- No human mouse/keyboard session was run. The evidence is from the running game's
  viewport and the scripted demo.

## Evidence

All images are offscreen viewport captures from the running Godot game, not
mockups or desktop screenshots.

| File | Contents |
| --- | --- |
| `m41b-first-person-pickaxe.png` | First-person wooden pickaxe in the arena. |
| `m41b-first-person-axe.png` | First-person stone axe. |
| `m41b-first-person-shovel.png` | First-person iron shovel. |
| `m41b-first-person-sword.png` | First-person diamond sword. |
| `m41b-first-person-axe-swing.png` | First-person axe at the swing peak. |
| `m41b-third-person-rear.png` | Third-person rear view, character left of the crosshair, pickaxe in hand. |
| `m41b-third-person-walking.png` | Third-person walking. |
| `m41b-third-person-jumping.png` | Third-person jump. |
| `m41b-third-person-swing.png` | Third-person pickaxe swing. |
| `m41b-third-person-sword.png` | Third-person diamond sword. |
| `m41b-character-preview.png` | Character screen with the shared model. |
| `m41b-settings-camera.png` | Settings with Camera view, distance and side offset. |
| `m41b-before-after.png` | Old M41 vs M41b first- and third-person comparison. |
| `m41b-camera-demo.gif` | Ten-frame sequence of the above demo frames. |
| `m41b-demo-manifest.json` | Frame notes, camera distance and shoulder offset. |

Capture command:

```powershell
godot --path godot --script res://scripts/tests/run_camera_demo.gd
```

The demo boots the real game scene, builds the project's existing
`VisualTestArena`, stages the player on the path, and captures the frames while
walking, jumping, swinging and switching tools. It is evidence tooling, not game
code.

## Repository state

The worktree already contained uncommitted M41 work when this correction began.
Those changes were preserved. No commit was made in this pass; the repository is
left in a consistent, test-passing state for the user's normal review/commit
workflow.
