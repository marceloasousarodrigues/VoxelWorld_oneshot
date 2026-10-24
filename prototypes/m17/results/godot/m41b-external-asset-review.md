# M41b - External Asset Review

Status: **research complete; nothing integrated.**

Scope: find specific, usable resources for stylised voxel-compatible tools,
better player/first-person hands, compatible humanoid animations, Godot 4
over-the-shoulder camera components, and consistent item icons. The review
started with Quaternius, Kenney and the Godot Asset Library, then checked KayKit
and the Phantom Camera project as reputable alternatives.

Method:

- Inspected the actual preview art for each model pack, not just the store copy.
  The inspected previews are saved under
  `prototypes/m17/results/godot/m41b-asset-previews/`.
- Read the formats, licence, animation/rig claims and engine-compatibility notes
  on each source page.
- Checked the Godot Asset Library search for camera components; its filtered
  result page did not return a stable match for this term, so Phantom Camera was
  verified against its GitHub source, README and third-person follow-mode docs.
- Compared the visual style and proportion against the current VoxelWorld arena,
  player and tool captures (`m41b-first-person-pickaxe.png`,
  `m41b-third-person-rear.png`).
- Did **not** download or import any asset pack. The preview images are for
  assessment only. No third-party model, texture or animation is shipped in the
  game.

## Candidates

| Rank | Candidate | Source | Licence | Format | Style / characteristics | Compatibility | Integration effort | Suitability |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **Quaternius Cube World Kit** | <https://quaternius.com/packs/cubeworldkit.html> | CC0 | FBX, OBJ, glTF, Blend | 108 models, animated, textured; cube/voxel characters, animals, enemies, blocks, trees and simple tools | High. The closest external match to VoxelWorld's cube aesthetic. Character proportions are different (larger head, shorter body) and the tools are simpler than the new in-house set. | Medium: import GLTF, remap materials, rescale, replace the procedural player/attach points, test animations. | **Best style match, but not needed now.** Useful as a reference and a future player/NPC/prop source. |
| 2 | **KayKit Adventurers** | <https://kaylousberg.itch.io/kaykit-adventurers> | CC0 | FBX, GLTF | 5 characters (+3 paid), 25+ weapons/shields/accessories, rigged and animated, single 1024 gradient atlas, smooth stylised low-poly | Low-medium. High quality, but the smooth rounded style clashes with the voxel world. | High: art-direction shift, material remap, rig/scale work, animation retargeting, item attachment. | **Not now.** Only makes sense if the whole game moves to a smooth low-poly look. |
| 3 | **Kenney Voxel Pack** | <https://kenney.nl/assets/voxel-pack> | CC0 | 2D PNG, 128x128 | 190 files; voxel-style pixel icons for tools, blocks, characters and animals | High for 2D icons; low for 3D props (it is a 2D pack). | Low for an icon reskin. | **Icon fallback only.** The current Minetest icons already match the world; a reskin would need a deliberate UI pass. |
| 4 | **Phantom Camera** | <https://github.com/ramokz/phantom-camera>; docs <https://phantom-camera.dev/follow-modes/third-person> | MIT | Godot 4 addon (GDScript/C#) | Cinemachine-like camera addon; third-person follow mode uses a `SpringArm3D`; follow offset, damping, spring length, collision mask, rotation offsets, priority and tweens | High engine compatibility (Godot 4.4+, 3.6k stars). It would replace the current custom camera rig. | Medium-high: install addon, rebuild the rig, preserve eye/crosshair targeting, rerun integration tests. | **Strong component, not needed now.** The current rig already passes collision and crosshair tests. Revisit if advanced damping/reframing is required. |
| 5 | **Quaternius Universal Animation Library** | <https://quaternius.com/packs/universalanimationlibrary.html> | CC0 | FBX, GLB, Blend | 120+ animations on a universal humanoid rig; tested in Godot, Unity and Unreal | Medium. The animations are excellent, but VoxelWorld's player is a box-built node hierarchy, not a skinned humanoid. | High: adopt a skinned humanoid rig, retarget, test the full locomotion/combat set. | **Future only.** The right choice if the player becomes a rigged character. |
| 6 | **Quaternius Modular Weapons Pack** | <https://quaternius.com/packs/medievalweapons.html> | CC0 | FBX, OBJ, Blend | 24 medieval weapons and shields; smooth low-poly, untextured flat colours | Low. Swords, axes and shields are high quality but visibly smoother/rounder than the voxel world. | Low-medium for props, but a style mismatch. | **No.** Would clash with the voxel tools and world. |
| 7 | **Kenney Blocky Characters** | <https://kenney.nl/assets/blocky-characters> | CC0 | 3D, animated | 20 blocky characters; modern/urban outfits, thin limbs, no medieval tools | Partial. Blocky, but not the same proportion or genre. | Medium: import, remap, replace model, add tools. | **No.** Wrong character/wardrobe for a medieval voxel game. |
| 8 | **Quaternius Universal Base Characters** | <https://quaternius.com/packs/universalbasecharacters.html> | CC0 | FBX, glTF, Blend | 6 base models, 20 hairstyles, ~13k triangles, semi-realistic | Low. Realistic proportions and smooth shading; not voxel. | High: full character/art-direction replacement. | **No.** |
| 9 | **Mixamo** | <https://www.mixamo.com> | Adobe terms, not CC0 | FBX | Large humanoid animation library | Medium technically; licensing/account restrictions and no redistribution of the source animations. | Medium-high plus legal review. | **No.** The project currently ships no external runtime assets and should not add a non-CC0 dependency for this. |

## Visual evidence

The preview images are saved in
`prototypes/m17/results/godot/m41b-asset-previews/`:

| Preview | What it shows |
| --- | --- |
| `quaternius-cubeworld.jpg` | Cube/voxel characters, animals, blocks, trees and simple pickaxe/axe/shovel/sword props. The closest visual match. |
| `quaternius-weapons.jpg` | Smooth low-poly swords, axes, shields, hammers and bows. Good craft, wrong surface language for voxel. |
| `quaternius-animations.jpg` | The smooth universal humanoid rig and animation poses. |
| `quaternius-basecharacters.jpg` | Semi-realistic base characters; clearly not voxel. |
| `kenney-voxel-pack.png` | 2D voxel-style icons, blocks, characters and tools. |
| `kenney-blocky-characters.png` | Blocky modern characters; no medieval tool set. |
| `kaykit-adventurers.png` | High-quality smooth stylised adventurers, weapons and shields. |

Phantom Camera was inspected through its README and its third-person follow-mode
documentation rather than a model preview; the relevant evidence is the
`SpringArm3D` third-person mode, collision mask, spring length, follow offset,
damping and rotation-offset properties documented at the URL above.

## Ranked shortlist and recommendation

**Recommendation for M41b: integrate none of them.**

The in-house correction pass already produced the smallest set of changes that
substantially improved the result:

1. **Tools/hands:** the procedural `ItemPresentation` + `HeldItemVisual` +
   `FirstPersonArms` pass. No external download, no licence obligation, exact
   match to the real item ids and tiers.
2. **Player:** the shared `PlayerCharacter` detail pass. It keeps the existing
   controller, preview, inventory and attachment points intact.
3. **Camera:** the existing custom rig, now with a two-stage collision-safe
   shoulder offset. Phantom Camera is a credible replacement, but replacing a
   working, tested rig adds risk without a demonstrated gameplay benefit.
4. **Icons:** the current Minetest-derived icons still match the world. If a
   future UI pass needs new icons, render the actual 3D tool models through a
   Godot `SubViewport` with an orthographic camera and nearest filtering. That
   keeps the icon and the held prop consistent and adds no external dependency.
   Kenney Voxel Pack is a fallback only.

If a later milestone deliberately changes the art direction, the smallest useful
external set would be:

- **Quaternius Cube World Kit** for one voxel-compatible player/NPC body and
  simple world props; and
- **Quaternius Universal Animation Library** only after a skinned humanoid rig is
  adopted; or **KayKit Adventurers** if the project chooses a smooth stylised
  look instead of voxel.

Do not combine Cube World Kit, KayKit and Modular Weapons in one pass: their
surface languages are different and the result would look less coherent than the
current procedural set.

## Licence notes

- **CC0** (Quaternius, Kenney, KayKit): free for personal and commercial use, no
  attribution required. Still record the source in `ASSET_MANIFEST.md` if any
  asset is ever imported.
- **MIT** (Phantom Camera): requires the copyright/licence notice to be retained.
  It is a code addon, not an art asset.
- **Mixamo/Adobe**: not CC0; account and redistribution terms apply. Not
  recommended for a zero-dependency repository.
- The preview images in `m41b-asset-previews/` are included only as review
  evidence; they are not game assets and are not loaded by the project.

## What would change the recommendation

- A future milestone explicitly asks for a rigged, animated humanoid player or
  NPCs: then evaluate Quaternius Cube World Kit (style) or KayKit Adventurers
  (quality) with a side-by-side runtime capture.
- A future camera milestone needs damping, reframing, priority cameras or
  Cinemachine-style blends: prototype Phantom Camera in a branch and rerun the
  M41 camera/aiming integration section before replacing the custom rig.
- A future UI milestone asks for a full icon reskin: prefer rendering the real 3D
  models to icons; use Kenney Voxel Pack only if a 2D icon set is explicitly
  wanted.
