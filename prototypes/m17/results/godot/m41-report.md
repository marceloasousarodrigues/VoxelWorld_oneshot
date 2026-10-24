# M41 - Player Character, First-Person Arms and Third-Person Camera

Status: **COMPLETE**, with the limitations listed at the end.

## What was added

### One player, two views

`VoxelPlayer` remains the single authoritative `CharacterBody3D`. It now owns:

- the existing first-person `Camera3D` at eye height;
- a camera-local `FirstPersonArms` model;
- a shared `PlayerCharacter` body, also used by the inventory Character preview;
- a rear `Camera3D` on a pitch pivot, with a small over-the-shoulder offset.

Switching views only changes which camera is current and which visual is visible.
Position, velocity, flight state, yaw/pitch, hotbar selection, inventory, survival
state, world edits and mouse capture are untouched. `F4` drives the new
`toggle_camera` InputMap action. F5 was deliberately not used because it already
saves the game.

### First person

- Visible voxel forearm, hand and thumb, with a small off hand at the frame edge.
- The held item is rebuilt from `Inventory.selected_item()` whenever the hotbar
  changes: blocks use their real six face textures, tools are 3D voxel props with
  tier-coloured heads, and food/materials use their transparent sprite art.
- Walk bob, jump lift, look sway and a repeatable swing pose. Mining restarts the
  swing on a fixed rhythm; breaking, attacking, placing and using food/farming
  items start one swing.
- All first-person parts disable shadow casting and sit below the reticle. A unit
  test reads the real mesh AABBs in camera-local space to prove no arm, hand or
  item geometry reaches the reticle, including at swing peaks.

### Third person

- Full articulated voxel body: shoulder and hip pivots animate walk, jump and
  swing while the body faces the controller's `-Z` forward direction.
- Rear camera at an adjustable distance (Settings, default 3.5 m) with a 0.35 m
  shoulder offset. The character sits left of the reticle.
- Collision uses a sphere shape cast against the voxel world's collision layer,
  excluding the player's own body. The arm shortens immediately when blocked and
  extends smoothly when clear, so it cannot pass through terrain, walls or trees.
  The body is hidden only if collision forces the camera inside it.
- The selected item is visible in the right hand. The inventory Character preview
  uses the same model and now also shows the selected item.

### Shared gameplay

- `eye_position()` and `aim_direction()` are the single targeting origin and
  direction for both views. In third person the direction converges from the eye
  to the rear camera's crosshair focus, preserving the existing reach and the
  alignment of the placement preview with `place_selected()`.
- Creature targeting, block targeting, mining, attacks, placement, food use,
  planting, fertilising, inventory, crafting, stations, saving and settings all
  run through the same code paths as before.
- Settings adds a live Camera view selector, a third-person distance slider and
  the F4 hint. Values are persisted in `user://voxelworld_settings.cfg`.
- F4 is ignored while any modal interface owns input. Opening/closing menus never
  changes the current view and never moves the player.

## Files

- `godot/scripts/game/player_character.gd` - shared articulated body.
- `godot/scripts/game/first_person_arms.gd` - camera-local arms and animation.
- `godot/scripts/game/held_item_visual.gd` - blocks, voxel tools and sprite items.
- `godot/scripts/game/voxel_player.gd` - camera rig, modes, targeting, animation
  and swing triggers.
- `godot/scripts/game/character_preview.gd` - reuses `PlayerCharacter`.
- `godot/scripts/game/inventory_panel.gd` - pushes the held item into the preview.
- `godot/scripts/game/settings_panel.gd` and
  `godot/scripts/core/game_settings.gd` - camera view and distance settings.
- `godot/project.godot` - `toggle_camera` action (F4).
- `godot/scripts/tests/test_player_visuals.gd`,
  `test_settings.gd` and `run_integration.gd` - new coverage.
- `godot/scripts/tests/run_camera_demo.gd` - staged runtime frame capture.

## Validation

Godot 4.7.2, canonical project `godot/`.

- Unit suite: `M17_TESTS_PASS 3477 assertions`.
- Integration suite: `M17_INTEGRATION_PASS 620 assertions`.
- Regression: `M17_REGRESSION_PASS assertions=52`.

The new integration section exercises the real F4 action and verifies:

- default first person, arms visible, body hidden;
- repeated switching, exactly one current camera, position/hotbar/inventory/mouse
  and world edits unchanged;
- open-space rear distance and a wall behind the player shortening the camera
  without crossing the wall, then extending after removal;
- turning and jumping with a finite, stable rear camera;
- third-person target, placement preview cell/block/orientation, placement,
  tool mining and creature attack;
- inventory and settings ownership, live camera setting changes, ignored F4 while
  a menu is open, and restoration of the previous view on close.

The new unit module verifies:

- first person is the default and the body/arms visibility follows the mode;
- arm and item geometry stays below the reticle at rest and through the swing;
- no first-person part casts a shadow;
- model height, facing direction, same look direction and camera distance;
- repeated toggles leave a valid current camera;
- selected tools/blocks propagate to both models;
- the shared Character preview model and the settings round-trip.

## Evidence

All images below are offscreen viewport renders from the running game, not
mockups or desktop screenshots.

| File | Contents |
| --- | --- |
| `m41-first-person.png` | First person with the wooden pickaxe in hand. |
| `m41-first-person-sword.png` | First person with the diamond sword. |
| `m41-third-person.png` | Third person on a flat pad, character offset left, stone block in hand, placement ghost visible. |
| `m41-third-person-sword.png` | Third person in open air with the diamond sword at the character's side. |
| `m41-character-preview.png` | Character screen using the shared model with the selected wooden axe. |
| `m41-settings-camera.png` | Settings showing Camera view, Camera distance and the F4 hint. |
| `m41-camera-demo.gif` | Eight-frame sequence: first person, third idle, walking, jumping, swing, placement before/after, first-person swing. |
| `m41-demo-00.png` ... `m41-demo-07.png` | The source frames of the GIF. |
| `m41-demo-manifest.json` | Frame notes and camera/action metadata. |

Capture commands used:

```powershell
godot --path godot -- --capture --capture-name=m41-first-person.png --settle=6 `
  --tools --render-distance=5 --camera-mode=first --look=38,-12 --seed=17017

godot --path godot -- --placement-capture=cube --capture-name=m41-third-person.png `
  --settle=6 --render-distance=5 --camera-mode=third --camera-distance=4 --seed=17017

godot --path godot -- --capture --capture-name=m41-third-person-sword.png --settle=6 `
  --tools --select-slot=3 --render-distance=5 --camera-mode=third --camera-distance=4 `
  --player-at=8.5,120,8.5 --fly --look=0,-35 --seed=17017

godot --path godot --script res://scripts/tests/run_camera_demo.gd
```

## Limitations

- VoxelWorld has no exported player mesh. The character and arms are the
  project's box-built voxel models, not a high-detail rig.
- Equipment/armour is not implemented, so the character shows no armour. The
  Character screen continues to mark equipment slots as unavailable.
- No front-facing third-person mode was added; the task marked it as an optional
  later extension.
- First-person hands are deliberately simple: no fingers or per-item grip poses.
- The first-person held tool is a 3D voxel prop, not a port of the 2D icon's exact
  pixels.
- No human mouse/keyboard play session was run. Visual assessment used the
  running-game captures and the scripted demo; automated tests cover input and
  state paths.
