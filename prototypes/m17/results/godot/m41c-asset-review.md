# M41c - External Asset Review

Status: **research complete; nothing integrated.** This review is about held-tool
geometry and hand presentation. It does not change the project's existing
textures or engine dependencies.

## Method

- Read the publisher page, licence and supported formats for each candidate.
- Inspected the actual preview art, not just the store copy. The Quaternius
  preview is the same file captured in M41b at
  `prototypes/m17/results/godot/m41b-asset-previews/quaternius-cubeworld.jpg`.
- Downloaded the **Kenney Voxel Kit 1.0** archive to
  `%TEMP%\m41c-assets\kenney-voxel-kit-1.0.zip`, outside the repository, and
  extracted it to inspect the actual mesh inventory. It was not imported.
- Did not download any pack into the project. No third-party model, texture or
  animation is shipped or loaded by the game after this pass.
- Compared silhouettes, polygon/part density, texture use, scale/origin
  suitability, grip suitability and surface language against the existing
  VoxelWorld arena and the M41b held-item model.

## Candidates

| Candidate | Source | Licence | Actual content | Held-tool suitability | Decision |
| --- | --- | --- | --- | --- | --- |
| **Quaternius Cube World Kit** | <https://quaternius.com/packs/cubeworldkit.html> | CC0 1.0 | 108 models; animated and textured; FBX, OBJ, Blend, glTF. The preview shows voxel characters, animals, blocks, trees and simple pickaxe/axe/shovel/sword props. | The style is close, but the tools in the preview are simpler than the M41c target: small, flat T-shaped heads and little or no material separation. They would not beat a purpose-built held model. The pack remains a good future source for NPC bodies and simple world props. | **Reference only, not imported.** |
| **Kenney Voxel Kit** | <https://kenney.nl/assets/voxel-kit> | CC0 1.0 | 48 files, 3D. The extracted archive contains 47 `block N` cube meshes plus a base block, one material and FBX/glTF/OBJ copies. There are no tools, hands or weapons. | None. It is a cube construction kit, not a held-item source. | **Not usable for this milestone.** |
| **Kenney Voxel Pack** | <https://kenney.nl/assets/voxel-pack> | CC0 1.0 | 2D, 128 x 128 pixel tiles, 190 files. The publisher labels the category **2D**. | The pack contains voxel-style item icons, not 3D geometry. It cannot supply a held model. It remains an icon fallback only. | **Do not treat as a 3D source.** |
| **KayKit Adventurers** (checked in M41b) | <https://kaylousberg.itch.io/kaykit-adventurers> | CC0 | 3D rigged characters and 25+ weapons/shields with a smooth low-poly gradient atlas. | High individual quality, but the smooth rounded surface language clashes with VoxelWorld's flat voxel world and would require an art-direction change. | **No.** |
| **Quaternius Modular Weapons** (checked in M41b) | <https://quaternius.com/packs/medievalweapons.html> | CC0 | 24 smooth low-poly medieval weapons and shields. | Good props in isolation, but visibly smoother/rounder than the voxel world. | **No.** |
| **Quaternius Universal Animation Library / Universal Base Characters** (checked in M41b) | <https://quaternius.com/packs/universalanimationlibrary.html>, <https://quaternius.com/packs/universalbasecharacters.html> | CC0 | Rigged humanoid animations and semi-realistic base characters. | VoxelWorld's player is a box-built node hierarchy, not a skinned humanoid. Adopting these would be a character-architecture change, not a hand/tool polish. | **Future only if the player becomes a skinned rig.** |
| **Phantom Camera** (checked in M41b) | <https://github.com/ramokz/phantom-camera> | MIT | Godot 4 camera addon. | The existing custom camera rig already passes collision, aiming and crosshair-convergence tests. Replacing it is not required and would risk the preserved M41b behaviour. | **No; camera untouched.** |

## Why the in-house geometry was retained

The existing procedural tools already have exact access to the real item IDs,
tier colours, first-person scale, grip origin and the project's flat-shaded
voxel language. The external packs either:

- contain no tool geometry (Kenney Voxel Kit),
- are 2D (Kenney Voxel Pack),
- are the wrong surface language (KayKit, Quaternius Modular Weapons), or
- have tools that are simpler than the target (Quaternius Cube World Kit).

Rebuilding the in-house tools therefore gives the best match with the least
risk and no new dependency. The supplementary model inspection render is
`prototypes/m17/results/godot/m41c-model-lineup.png`.

## Licence notes

- **Quaternius, Kenney and KayKit:** CC0 1.0; free for personal and commercial
  use; attribution not required. If any of these are imported in a future
  milestone, record the source and licence in `godot/ASSET_MANIFEST.md`.
- **Phantom Camera:** MIT; if ever integrated, retain the copyright/licence
  notice.
- The downloaded Kenney archive and the extracted files are only in the local
  temporary directory. They are not part of the repository and are not loaded by
  the game.
- No external preview image is used as a texture, billboard or model. The
  preview files are review evidence only.

## What would change this decision

- A future milestone explicitly changes the art direction to smooth low-poly, or
  adopts a skinned humanoid player. Then KayKit/Quaternius characters and
  weapons could be evaluated as a coherent set.
- A future milestone needs many NPCs or world props and wants to replace the
  box-built character props. Quaternius Cube World Kit is the closest style
  match for that purpose, subject to a runtime side-by-side comparison.
- A future held-item milestone would need a much larger library of modelled
  tools than the game's 16 tool items. A pack could then save modelling time,
  but it would still need grip-pivot and scale customisation.
