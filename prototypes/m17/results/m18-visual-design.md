# M18 — VoxelWorld visual design specification

Status: active. This is the visual contract for the Godot implementation under
`prototypes/m17/godot/`. It describes the style the renderer and world content
are being tuned to, not an aspiration disconnected from the game.

## 1. Direction

**Polished stylized voxel survival.** The world stays block-native, but it must
read as a deliberate place rather than a debug scene:

- clear silhouettes before surface noise;
- broad, readable material families (soil, stone, sand, wood, foliage, water);
- a restrained natural palette with a warm sun and cool shadows;
- visible depth through contact darkness, atmospheric haze and a sky that
  changes across the day;
- dense enough vegetation to frame views, sparse enough to keep navigation and
  block reading easy.

Reference points: the restrained colour of *Eco*, the readable block language of
*Minecraft* with modern lighting, and the soft atmospheric depth of stylized
survival games. Do not chase photorealism.

## 2. Material rules

- A block is one metre. Texture scale is one tile per metre on cube faces.
- Every cube face samples exactly one `Texture2DArray` layer (`UV2.x` integer,
  no `+0.5` offsets). Mipmaps and anisotropic filtering are mandatory.
- Magnification stays crisp; minification is allowed to soften through mipmaps.
  Texture crawl/shimmer is a defect, not a style choice.
- Base palette is graded away from neon saturation:
  - grass/foliage: sage to forest green, never fluorescent;
  - soil: warm umber, not orange;
  - stone: neutral cool grey with readable darks;
  - sand: warm cream, not white;
  - water: teal-blue in shallows, deep blue in the distance.
- Biome tint is applied to grass tops, foliage and vegetation. Grass *sides*
  keep their dirt colour so vertical faces do not turn into green slabs.
- Low-frequency world-space variation (large soft patches) breaks repetition.
  No per-pixel noise that hides block edges or gameplay information.
- Vertex ambient occlusion is baked into chunk meshes. It is the primary source
  of contact depth; screen-space AO is a subtle addition, not a substitute.

## 3. Geometry rules

- Terrain is voxel geometry. No smoothing that changes collision.
- Trees: readable trunk, taper and layered canopy. Oak canopies are rounded and
  slightly irregular; pines are conical tiers. No floating rectangular slabs.
- Decoration (grass tufts, ferns, shrubs) uses crossed quads, slightly inset and
  biome-tinted, and must not z-fight with the ground.
- Important stations are recognizable objects, not retextured cubes:
  - **Crafting table**: overhanging plank top with a framed working surface,
    four legs and side aprons. Silhouette readable at 10 m.
  - **Furnace**: masonry body with a plinth, a top cap, a recessed dark opening
    and a controlled warm ember glow. Readable from front and side.
- Custom station geometry stays inside the one-metre voxel cell, keeps the full
  cube as its logical/collision identity, and is emitted by the chunk mesher (no
  per-block scene nodes).
- Rocks, ore outcrops and resource blocks are clustered so they read as objects
  rather than single random pixels.

## 4. Lighting and atmosphere

- One directional sun/moon light; the moon reuses the sun node with a cool,
  low-energy colour and a clamped-above-horizon direction.
- Shadows: four-way split, near shadows crisp enough to ground objects; no
  visible peter-panning or acne. Shadow distance stays around 96 m.
- Sky: layered gradient, warm horizon at dawn/dusk, subtle sun/moon disc, slow
  cloud layer, sparse stars at night. The horizon must never become a flat
  grey band.
- Fog: gentle exponential haze that gives distance without bleaching the
  palette; sky and fog colours stay related at every time of day.
- Night must remain navigable: silhouettes and nearby materials readable, not
  crushed to black. No washed-out daylight.
- Exposure/tonemapping is global and stable. No per-biome exposure hacks.

## 5. Water

- Water is a transparent surface with depth-dependent absorption: clear at the
  shoreline, deeper and darker offshore.
- Surface normals are gently animated; the highlight is controlled and tied to
  the sun.
- Source water surfaces form one flat level. No checkerboard animation and no
  stair-stepped ocean surface.
- Chunk borders must not show a water seam; world-space UVs/normals are used.
- Water keeps the existing logical fluid simulation, save/load and editing
  behaviour.

## 6. Quality targets

- 1280×720 window, render distance 5, seed 17017, RTX 3080 / i7-10700K class
  hardware: median frame time ≤ 8 ms, p95 ≤ 16.7 ms during normal movement,
  no new multi-frame stalls from rendering or mesh attachment.
- Draw calls must not grow materially from the M18 baseline (≈384 at the spawn
  view, radius 5).
- No texture shimmer, atlas bleed, missing faces, seams, z-fighting or water
  surface stair-stepping in inspected captures.
- Day, sunset, twilight and night must all be visually usable.

## 7. Test area

`--visual-test` builds a deterministic showcase at world (72, 65, −88) in the
forest near spawn, using the production voxel world, mesher, materials and
streamer. It contains material pads, terraces, a pond and shoreline, natural and
planted trees, boulders/ore outcrop, crafting table, furnace and other
placeables. `--visual-test=close|normal|wide` selects fixed viewpoints. Captures
freeze the clock with `--time=` so before/after images are comparable.
