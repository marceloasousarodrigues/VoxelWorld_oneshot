class_name ChunkMesher
extends RefCounted

const BlockShape = preload("res://scripts/core/block_shape.gd")

## Builds a chunk's render mesh and its derived collision mesh from logical
## voxel data.
##
## Design notes:
## - Only visible faces are emitted (a face is skipped when its neighbour hides
##   it), so interior faces never reach the GPU.
## - A padded 18^3 block copy is built first so border lookups against the six
##   neighbour chunks are plain index arithmetic instead of per-face world
##   queries.
## - Faces are grouped into five render layers (opaque, cutout, blend, water,
##   deco); each becomes one mesh surface with its own material.
## - Texture layer indices travel in `ARRAY_TEX_UV2.x`, vertex colour carries
##   face shading multiplied by biome tint.

const PAD := ChunkData.SIZE + 2
const PADDED_CELLS := PAD * PAD * PAD
const LAYER_CELLS := ChunkData.SIZE * ChunkData.SIZE

## Neighbour offset into the padded buffer for each face, in face order
## (PX, NX, PY, NY, PZ, NZ).  Using strides keeps the hottest loop free of
## per-face index arithmetic and function calls.
const FACE_STRIDE := [1, -1, PAD * PAD, -PAD * PAD, PAD, -PAD]

const FACE_NORMALS := [
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
	Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
]
const FACE_NORMAL_I := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Half-face patch axes in the same order used by BlockShape.boundary_mask.
const FACE_TANGENT_AXES := [
	Vector2i(1, 2), Vector2i(1, 2), Vector2i(0, 2),
	Vector2i(0, 2), Vector2i(0, 1), Vector2i(0, 1),
]
const FACE_NORMAL_AXIS := [0, 0, 1, 1, 2, 2]
const FACE_CORNERS := [
	[Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5)],
	[Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5)],
	[Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5)],
	[Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
	[Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
	[Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5)],
]
const FACE_UVS := [
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
]
## Godot winds front faces so the right-hand-rule normal of the triangle points
## *into* the solid (see `BoxMesh`).  With the opposite order every face was a
## back face: `cull_back` hid all outward surfaces and the collision trimesh
## reported inverted normals, so the player fell through the ground.
const QUAD_INDICES := [0, 2, 1, 0, 3, 2]
## Face shading: top faces catch the most light, bottom faces the least.
const FACE_SHADE := [0.84, 0.84, 1.0, 0.52, 0.70, 0.70]
## Flattened (face * 4 + corner) offsets for the two in-plane AO neighbours and
## the diagonal.  These are `PADDED_STRIDE` combinations, precomputed so the
## hot emit loop never builds Vectors or loops over axes.
const AO_OFFSET_A := [
	-324, 324, 324, -324,  # PX
	-324, 324, 324, -324,  # NX
	-1, 1, 1, -1,          # PY
	-1, 1, 1, -1,          # NY
	1, 1, -1, -1,          # PZ
	-1, -1, 1, 1,          # NZ
]
const AO_OFFSET_B := [
	-18, -18, 18, 18,      # PX
	18, 18, -18, -18,      # NX
	18, 18, -18, -18,      # PY
	-18, -18, 18, 18,      # NY
	-324, 324, 324, -324,  # PZ
	-324, 324, 324, -324,  # NZ
]
const AO_OFFSET_DIAGONAL := [
	-342, 306, 342, -306,  # PX
	-306, 342, 306, -342,  # NX
	17, 19, -17, -19,      # PY
	-19, -17, 19, 17,      # NY
	-323, 325, 323, -325,  # PZ
	-325, 323, 325, -323,  # NZ
]
## How dark a fully occluded vertex gets.  0.22 gives four readable steps
## (1.0, 0.78, 0.56, 0.34) without turning crevices black.
const AO_STRENGTH := 0.22
## Slow per-block brightness variation, keyed by world cell.  It breaks the
## tiled look without hiding face boundaries.
const VARIATION_MIN := 0.945
const VARIATION_RANGE := 0.11
const WATER_RENDER_HEIGHT := 0.875
## Layers that make up the shadow-casting chunk mesh; water is a separate mesh
## so it never casts shadows and sorts independently.
const SOLID_LAYERS := [BlockDB.LAYER_OPAQUE, BlockDB.LAYER_CUTOUT, BlockDB.LAYER_BLEND, BlockDB.LAYER_DECO]

var library: TextureLibrary
var materials: VoxelMaterials
var face_layer: PackedInt32Array = PackedInt32Array()
## 1 when a block casts baked ambient occlusion (opaque, leaves, cactus).
var _occluder: PackedByteArray = PackedByteArray()
var _buffers: Array = []
var _collision := {"vertex": PackedVector3Array(), "index": PackedInt32Array()}
var _padded: PackedByteArray = PackedByteArray()
var _padded_orientation: PackedByteArray = PackedByteArray()
var _padded_fluid: PackedByteArray = PackedByteArray()
## Reused ambient-occlusion scratch (four corner factors) so per-face AO does
## not allocate inside the hot emit loop.
var _ao_scratch: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
## Reused "no AO" marker for cutout/transparent faces, which do not get baked
## contact darkening (their many overlapping leaf faces made AO expensive and
## visually noisy).
var _no_ao: PackedFloat32Array = PackedFloat32Array()
var stats := {"builds": 0, "faces": 0, "triangles": 0, "ms": 0.0, "fill_ms": 0.0, "emit_ms": 0.0, "assemble_ms": 0.0}


func _init(texture_library: TextureLibrary, voxel_materials: VoxelMaterials = null) -> void:
	library = texture_library
	materials = voxel_materials if voxel_materials != null else VoxelMaterials.new(texture_library)
	_resolve_layers()
	for layer in BlockDB.LAYER_COUNT:
		_buffers.append(_empty_surface())
	_padded.resize(PADDED_CELLS)
	_padded_orientation.resize(PADDED_CELLS)
	_padded_fluid.resize(PADDED_CELLS)


func _resolve_layers() -> void:
	face_layer.resize(BlockDB.COUNT * 6)
	_occluder.resize(BlockDB.COUNT)
	for block_id in BlockDB.COUNT:
		var keys: PackedStringArray = BlockDB.face_keys[block_id]
		for face in 6:
			face_layer[block_id * 6 + face] = library.layer_index(keys[face]) if not keys[face].is_empty() else 0
		var occludes := not BlockDB.is_open_model(block_id) and (BlockDB.is_opaque(block_id) \
			or block_id == BlockDB.OAK_LEAVES or block_id == BlockDB.PINE_LEAVES \
			or block_id == BlockDB.BIRCH_LEAVES or block_id == BlockDB.BLOSSOM_LEAVES \
			or block_id == BlockDB.CACTUS)
		_occluder[block_id] = 1 if occludes else 0


func _empty_surface() -> Dictionary:
	return {
		"vertex": PackedVector3Array(),
		"normal": PackedVector3Array(),
		"uv": PackedVector2Array(),
		"uv2": PackedVector2Array(),
		"color": PackedColorArray(),
		"index": PackedInt32Array(),
		"faces": 0,
	}


static func padded_index(x: int, y: int, z: int) -> int:
	return (x + 1) + PAD * ((z + 1) + PAD * (y + 1))


## Builds the mesh from live world data.  Kept for tests and the synchronous
## path: the streamer instead captures an input snapshot on the main thread and
## runs `build_input` on a worker thread.
## Returns `{"mesh": ArrayMesh?, "collision": ArrayMesh?, "faces": int, "ms": float}`.
func build(chunk: ChunkData, world: VoxelWorld) -> Dictionary:
	return build_input(capture_input(chunk, world))


## Main-thread snapshot of everything the mesh build reads: the chunk's own
## voxels and the six neighbour chunks' data.  `build_input` never touches the
## live world, so it is safe to run off the main thread while the player edits.
func capture_input(chunk: ChunkData, world: VoxelWorld) -> Dictionary:
	var neighbour_blocks: Array = []
	var neighbour_orientations: Array = []
	var neighbour_fluid: Array = []
	for face in 6:
		var neighbour: ChunkData = world.chunks.get(chunk.coord + FACE_NORMAL_I[face], null)
		if neighbour == null:
			neighbour_blocks.append(PackedByteArray())
			neighbour_orientations.append(PackedByteArray())
			neighbour_fluid.append(PackedByteArray())
		else:
			neighbour_blocks.append(neighbour.blocks.duplicate())
			neighbour_orientations.append(neighbour.orientations.duplicate())
			neighbour_fluid.append(neighbour.fluid.duplicate())
	return {
		"coord": chunk.coord,
		"blocks": chunk.blocks.duplicate(),
		"orientations": chunk.orientations.duplicate(),
		"fluid": chunk.fluid.duplicate(),
		"biomes": chunk.biomes.duplicate(),
		"neighbour_blocks": neighbour_blocks,
		"neighbour_orientations": neighbour_orientations,
		"neighbour_fluid": neighbour_fluid,
	}


## Pure mesh build from a `capture_input` snapshot.  Deterministic for a given
## snapshot and touches no engine resources, so it is safe to run on a worker
## thread; the caller turns the returned arrays into meshes with `assemble`.
## Returns `{"surfaces": Array, "collision": Dictionary, "faces": int, "ms": float}`.
func build_geometry(input: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	for surface: Dictionary in _buffers:
		surface["vertex"].clear()
		surface["normal"].clear()
		surface["uv"].clear()
		surface["uv2"].clear()
		surface["color"].clear()
		surface["index"].clear()
		surface["faces"] = 0
	_collision["vertex"].clear()
	_collision["index"].clear()

	_fill_padded(input)
	var after_fill := Time.get_ticks_usec()
	_emit_faces(input)
	var after_emit := Time.get_ticks_usec()

	# The mesher reuses its scratch buffers between builds, so the result has to
	# own copies before the next build can start.
	var surfaces: Array = []
	for layer: int in BlockDB.LAYER_COUNT:
		var surface: Dictionary = _buffers[layer]
		surfaces.append({
			"vertex": (surface["vertex"] as PackedVector3Array).duplicate(),
			"normal": (surface["normal"] as PackedVector3Array).duplicate(),
			"uv": (surface["uv"] as PackedVector2Array).duplicate(),
			"uv2": (surface["uv2"] as PackedVector2Array).duplicate(),
			"color": (surface["color"] as PackedColorArray).duplicate(),
			"index": (surface["index"] as PackedInt32Array).duplicate(),
			"faces": int(surface["faces"]),
		})

	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	stats["builds"] = int(stats["builds"]) + 1
	stats["ms"] = float(stats["ms"]) + elapsed
	stats["fill_ms"] = float(stats["fill_ms"]) + float(after_fill - started) / 1000.0
	stats["emit_ms"] = float(stats["emit_ms"]) + float(after_emit - after_fill) / 1000.0
	var faces := 0
	for surface: Dictionary in surfaces:
		faces += int(surface["faces"])
	stats["faces"] = int(stats["faces"]) + faces
	stats["triangles"] = int(stats["triangles"]) + faces * 2
	return {
		"surfaces": surfaces,
		"collision": {
			"vertex": (_collision["vertex"] as PackedVector3Array).duplicate(),
			"index": (_collision["index"] as PackedInt32Array).duplicate(),
		},
		"faces": faces,
		"ms": elapsed,
	}


## Turns a `build_geometry` result into engine meshes.  Runs on the main thread
## because it creates ArrayMesh and collision-shape resources.
func assemble(geometry: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var surfaces: Array = geometry["surfaces"]
	var mesh := _assemble_array_mesh(surfaces, SOLID_LAYERS)
	var water_mesh := _assemble_array_mesh(surfaces, [BlockDB.LAYER_WATER])
	var collision_arrays: Dictionary = geometry["collision"]
	var collision: ArrayMesh = null
	if not (collision_arrays["index"] as PackedInt32Array).is_empty():
		collision = ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = collision_arrays["vertex"]
		arrays[Mesh.ARRAY_INDEX] = collision_arrays["index"]
		collision.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	stats["assemble_ms"] = float(stats["assemble_ms"]) + float(Time.get_ticks_usec() - started) / 1000.0
	return {
		"mesh": mesh, "water_mesh": water_mesh, "collision": collision,
		"faces": int(geometry["faces"]), "ms": float(geometry["ms"]),
	}


## Combined path used by tests and the synchronous build: capture, build, assemble.
func build_input(input: Dictionary) -> Dictionary:
	return assemble(build_geometry(input))


func _fill_padded(input: Dictionary) -> void:
	var blocks: PackedByteArray = input["blocks"]
	var fluid: PackedByteArray = input["fluid"]
	# The padded buffer is reused between builds and only the interior plus the
	# slabs of *loaded* neighbours get overwritten below.  It must be reset first:
	# a slab whose neighbour is not loaded has to read as AIR (which only ever
	# draws extra faces), not as whatever the previously meshed chunk left there.
	# Without this reset the emitted geometry of a chunk on the edge of the loaded
	# region depends on the order the chunks happened to be meshed in.
	_padded.fill(BlockDB.AIR)
	_padded_orientation.fill(0)
	_padded_fluid.fill(ChunkData.NO_FLUID)
	var orientations: PackedByteArray = input["orientations"]
	for local_y in ChunkData.SIZE:
		for local_z in ChunkData.SIZE:
			var row := ChunkData.cell_index(0, local_y, local_z)
			var padded_row := padded_index(0, local_y, local_z)
			for local_x in ChunkData.SIZE:
				_padded[padded_row + local_x] = blocks[row + local_x]
				_padded_orientation[padded_row + local_x] = orientations[row + local_x]
				_padded_fluid[padded_row + local_x] = fluid[row + local_x]
	for face in 6:
		var neighbour_blocks: PackedByteArray = input["neighbour_blocks"][face]
		if neighbour_blocks.is_empty():
			continue
		_fill_padded_slab(neighbour_blocks, input["neighbour_orientations"][face],
			input["neighbour_fluid"][face], face)


func _fill_padded_slab(neighbour_blocks: PackedByteArray, neighbour_orientations: PackedByteArray,
		neighbour_fluid: PackedByteArray, face: int) -> void:
	match face:
		BlockDB.FACE_NX:
			for local_y in ChunkData.SIZE:
				for local_z in ChunkData.SIZE:
					var index := ChunkData.cell_index(ChunkData.SIZE - 1, local_y, local_z)
					var target := padded_index(-1, local_y, local_z)
					_padded[target] = neighbour_blocks[index]
					_padded_orientation[target] = neighbour_orientations[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_PX:
			for local_y in ChunkData.SIZE:
				for local_z in ChunkData.SIZE:
					var index := ChunkData.cell_index(0, local_y, local_z)
					var target := padded_index(ChunkData.SIZE, local_y, local_z)
					_padded[target] = neighbour_blocks[index]
					_padded_orientation[target] = neighbour_orientations[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_NY:
			for local_z in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var index := ChunkData.cell_index(local_x, ChunkData.SIZE - 1, local_z)
					var target := padded_index(local_x, -1, local_z)
					_padded[target] = neighbour_blocks[index]
					_padded_orientation[target] = neighbour_orientations[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_PY:
			for local_z in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var index := ChunkData.cell_index(local_x, 0, local_z)
					var target := padded_index(local_x, ChunkData.SIZE, local_z)
					_padded[target] = neighbour_blocks[index]
					_padded_orientation[target] = neighbour_orientations[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_NZ:
			for local_y in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var index := ChunkData.cell_index(local_x, local_y, ChunkData.SIZE - 1)
					var target := padded_index(local_x, local_y, -1)
					_padded[target] = neighbour_blocks[index]
					_padded_orientation[target] = neighbour_orientations[index]
					_padded_fluid[target] = neighbour_fluid[index]
		BlockDB.FACE_PZ:
			for local_y in ChunkData.SIZE:
				for local_x in ChunkData.SIZE:
					var index := ChunkData.cell_index(local_x, local_y, 0)
					var target := padded_index(local_x, local_y, ChunkData.SIZE)
					_padded[target] = neighbour_blocks[index]
					_padded_orientation[target] = neighbour_orientations[index]
					_padded_fluid[target] = neighbour_fluid[index]


func _emit_faces(input: Dictionary) -> void:
	var blocks: PackedByteArray = input["blocks"]
	var orientations: PackedByteArray = input["orientations"]
	var fluid: PackedByteArray = input["fluid"]
	var origin := VoxelWorld.chunk_origin(input["coord"])
	var base := Vector3(origin)
	var biomes: PackedByteArray = input["biomes"]
	# Hoist the definition tables and the padded buffer: this loop runs 4096 times
	# per chunk and every static member access or helper call is measurable.
	var padded := _padded
	var opaque := BlockDB.opaque
	var liquid := BlockDB.liquid
	var cull_same := BlockDB.cull_same
	var solid := BlockDB.solid
	var stride := FACE_STRIDE
	for index in ChunkData.CELLS:
		var block_id := int(blocks[index])
		if block_id == BlockDB.AIR:
			continue
		var local_x := index % ChunkData.SIZE
		var local_z := (index / ChunkData.SIZE) % ChunkData.SIZE
		var local_y := index / LAYER_CELLS
		var centre := Vector3(local_x + 0.5, local_y + 0.5, local_z + 0.5)
		var is_custom := BlockDB.custom_model[block_id] == 1
		var is_deco := not is_custom and solid[block_id] == 0 and liquid[block_id] == 0
		var tint := Color.WHITE
		var tinted := block_id == BlockDB.GRASS or block_id == BlockDB.DRY_GRASS or block_id == BlockDB.OAK_LEAVES \
				or block_id == BlockDB.PINE_LEAVES or block_id == BlockDB.BIRCH_LEAVES \
				or block_id == BlockDB.BLOSSOM_LEAVES or is_deco
		if tinted:
			tint = WorldGen.BIOME_TINTS[biomes[ChunkData.column_index(local_x, local_z)]]
		var variation := _cell_variation(origin + Vector3i(local_x, local_y, local_z))
		var body_tint := Color(tint.r * variation, tint.g * variation, tint.b * variation, 1.0)
		if tinted:
			var macro := _macro_tint(origin + Vector3i(local_x, local_y, local_z))
			body_tint = Color(body_tint.r * macro.r, body_tint.g * macro.g, body_tint.b * macro.b, 1.0)
		if BlockDB.is_flower(block_id):
			# Flower petals are a deliberate colour accent; a green biome multiply
			# would turn red and blue blossoms muddy.
			body_tint = Color(variation, variation, variation, 1.0)
		if BlockShape.is_shaped(block_id):
			_emit_shaped_block(block_id, int(orientations[index]), centre,
				padded_index(local_x, local_y, local_z), body_tint)
			continue
		if is_deco:
			_emit_deco(block_id, centre, body_tint)
			continue
		var layer := BlockDB.layer_of(block_id)
		var is_water := block_id == BlockDB.WATER
		if is_water:
			layer = BlockDB.LAYER_WATER
		var surface: Dictionary = _buffers[layer]
		var padded_centre := padded_index(local_x, local_y, local_z)
		if is_custom:
			_emit_custom(surface, centre, block_id, padded_centre)
		var surface_height := 1.0
		if is_water:
			var above := int(padded[padded_centre + stride[BlockDB.FACE_PY]])
			var level := int(fluid[index])
			# Source water (and any column with water above it) keeps a full
			# block surface, so an ocean forms one flat plane instead of a
			# stair-stepped mosaic; only genuinely flowing cells sit lower.
			if above == block_id or level >= 7:
				surface_height = 1.0
			else:
				surface_height = WATER_RENDER_HEIGHT * clampf(float(level) / 8.0, 0.125, 1.0)
		var is_liquid := liquid[block_id] == 1
		var culls := cull_same[block_id] == 1
		var world_cell := origin + Vector3i(local_x, local_y, local_z)
		for face in 6:
			var neighbour := int(padded[padded_centre + stride[face]])
			# A full cube next to a stair only loses the half-face patches the stair
			# actually occupies.  Keeping the uncovered patches avoids holes when
			# looking through the empty half of the stair cell.
			if not is_liquid and BlockShape.is_shaped(neighbour) \
					and BlockDB.hides_neighbour_face(block_id, neighbour):
				var neighbour_orientation := int(_padded_orientation[padded_centre + stride[face]])
				var covered := BlockShape.boundary_mask(neighbour, neighbour_orientation, face ^ 1)
				if covered == 0xF:
					continue
				var patch_tint := body_tint
				if (block_id == BlockDB.GRASS or block_id == BlockDB.DRY_GRASS) and face != BlockDB.FACE_PY:
					patch_tint = Color(variation, variation, variation, 1.0)
				for patch_index in 4:
					if (covered & (1 << patch_index)) != 0:
						continue
					if not is_custom and not is_water:
						_emit_face_patch(surface, centre, face, block_id, patch_tint,
							patch_index % 2, floori(float(patch_index) / 2.0))
					if solid[block_id] == 1:
						_emit_collision_patch(centre, face, patch_index % 2,
							floori(float(patch_index) / 2.0))
				continue
			# Inlined `BlockDB.hides_neighbour_face`, kept identical to that
			# helper by `test_block_db`.
			if neighbour != BlockDB.AIR:
				if is_liquid:
					if liquid[neighbour] == 1:
						continue
				elif opaque[neighbour] == 1:
					# Open station models (table/furnace) are not full cubes and
					# must not cull the ground/neighbour face beneath or beside
					# them; doing so left a visible hole under the table.
					if BlockDB.open_model[neighbour] == 0:
						continue
				elif neighbour == block_id and culls:
					continue
			if is_custom:
				# The custom model is not a cube, but its collision and logical
				# identity still are: keep the full-cube collision on every
				# exposed face and skip the cube's own render face.
				if solid[block_id] == 1:
					_emit_collision(centre, face)
			elif is_water:
				_emit_water_face(surface, centre, base + centre, face, FACE_NORMAL_I[face], surface_height, block_id, world_cell)
			else:
				# Grass keeps its biome tint on the top face only; its sides are
				# dirt and must not turn into green slabs.
				var face_tint := body_tint
				if (block_id == BlockDB.GRASS or block_id == BlockDB.DRY_GRASS) and face != BlockDB.FACE_PY:
					face_tint = Color(variation, variation, variation, 1.0)
				if layer == BlockDB.LAYER_OPAQUE:
					_face_ao_into(padded_centre, face)
					_emit_face(surface, centre, face, block_id, face_tint, 1.0, _ao_scratch)
				else:
					_emit_face(surface, centre, face, block_id, face_tint, 1.0, _no_ao)
				if solid[block_id] == 1:
					_emit_collision(centre, face)


func _emit_shaped_block(block_id: int, orientation: int, centre: Vector3,
		padded_centre: int, tint: Color) -> void:
	var padded := _padded
	var padded_orientation := _padded_orientation
	var surface: Dictionary = _buffers[BlockDB.layer_of(block_id)]
	for descriptor: Dictionary in BlockShape.exposed_faces(block_id, orientation):
		var cell: Vector3i = descriptor["cell"]
		var face: int = int(descriptor["face"])
		var neighbour_half := cell + BlockShape.FACE_STEPS[face]
		if neighbour_half.x < 0 or neighbour_half.x >= 2 \
				or neighbour_half.y < 0 or neighbour_half.y >= 2 \
				or neighbour_half.z < 0 or neighbour_half.z >= 2:
			var neighbour_index: int = padded_centre + int(FACE_STRIDE[face])
			var neighbour_id := int(padded[neighbour_index])
			if BlockDB.hides_neighbour_face(block_id, neighbour_id):
				if not BlockShape.is_shaped(neighbour_id):
					continue
				var adjacent := neighbour_half
				if adjacent.x < 0:
					adjacent.x = 1
				elif adjacent.x > 1:
					adjacent.x = 0
				if adjacent.y < 0:
					adjacent.y = 1
				elif adjacent.y > 1:
					adjacent.y = 0
				if adjacent.z < 0:
					adjacent.z = 1
				elif adjacent.z > 1:
					adjacent.z = 0
				if BlockShape.is_occupied(neighbour_id, int(padded_orientation[neighbour_index]), adjacent):
					continue
		var face_centre: Vector3 = centre + Vector3((float(cell.x) - 0.5) * 0.5,
			(float(cell.y) - 0.5) * 0.5, (float(cell.z) - 0.5) * 0.5)
		face_centre += (FACE_NORMALS[face] as Vector3) * 0.25
		_emit_half_face(surface, face_centre, face, block_id, tint)
		_emit_half_collision(face_centre, face)


func _emit_face_patch(surface: Dictionary, block_centre: Vector3, face: int, block_id: int,
		tint: Color, first_patch: int, second_patch: int) -> void:
	var axes: Vector2i = FACE_TANGENT_AXES[face]
	var face_centre: Vector3 = block_centre + (FACE_NORMALS[face] as Vector3) * 0.5
	face_centre[axes.x] += (float(first_patch) - 0.5) * 0.5
	face_centre[axes.y] += (float(second_patch) - 0.5) * 0.5
	_emit_half_face(surface, face_centre, face, block_id, tint)


func _emit_half_face(surface: Dictionary, face_centre: Vector3, face: int,
		block_id: int, tint: Color) -> void:
	var vertices: PackedVector3Array = surface["vertex"]
	var normals: PackedVector3Array = surface["normal"]
	var uvs: PackedVector2Array = surface["uv"]
	var uv2s: PackedVector2Array = surface["uv2"]
	var colors: PackedColorArray = surface["color"]
	var indices: PackedInt32Array = surface["index"]
	var axes: Vector2i = FACE_TANGENT_AXES[face]
	var corners: Array = FACE_CORNERS[face]
	var face_uvs: Array = FACE_UVS[face]
	var normal: Vector3 = FACE_NORMALS[face]
	var layer := face_layer[block_id * 6 + face]
	var shade: float = FACE_SHADE[face]
	var tone := Color(tint.r * shade, tint.g * shade, tint.b * shade, 1.0)
	var uv2 := Vector2(float(layer), 0.0)
	var base_index := vertices.size()
	for corner_index in 4:
		var corner: Vector3 = corners[corner_index]
		corner[axes.x] *= 0.5
		corner[axes.y] *= 0.5
		corner[FACE_NORMAL_AXIS[face]] = 0.0
		vertices.append(face_centre + corner)
		normals.append(normal)
		uvs.append(face_uvs[corner_index])
		uv2s.append(uv2)
		colors.append(tone)
	for quad_index in QUAD_INDICES:
		indices.append(base_index + quad_index)
	surface["faces"] = int(surface["faces"]) + 1


func _emit_collision_patch(block_centre: Vector3, face: int, first_patch: int,
		second_patch: int) -> void:
	var axes: Vector2i = FACE_TANGENT_AXES[face]
	var face_centre: Vector3 = block_centre + (FACE_NORMALS[face] as Vector3) * 0.5
	face_centre[axes.x] += (float(first_patch) - 0.5) * 0.5
	face_centre[axes.y] += (float(second_patch) - 0.5) * 0.5
	_emit_half_collision(face_centre, face)


func _emit_half_collision(face_centre: Vector3, face: int) -> void:
	var vertices: PackedVector3Array = _collision["vertex"]
	var indices: PackedInt32Array = _collision["index"]
	var axes: Vector2i = FACE_TANGENT_AXES[face]
	var corners: Array = FACE_CORNERS[face]
	var base_index := vertices.size()
	for corner_index in 4:
		var corner: Vector3 = corners[corner_index]
		corner[axes.x] *= 0.5
		corner[axes.y] *= 0.5
		corner[FACE_NORMAL_AXIS[face]] = 0.0
		vertices.append(face_centre + corner)
	for quad_index in QUAD_INDICES:
		indices.append(base_index + quad_index)
func _emit_face(surface: Dictionary, centre: Vector3, face: int, block_id: int, tint: Color, height_offset: float, ao: PackedFloat32Array = PackedFloat32Array(), glow: float = 0.0) -> void:
	var vertices: PackedVector3Array = surface["vertex"]
	var normals: PackedVector3Array = surface["normal"]
	var uvs: PackedVector2Array = surface["uv"]
	var uv2s: PackedVector2Array = surface["uv2"]
	var colors: PackedColorArray = surface["color"]
	var indices: PackedInt32Array = surface["index"]
	var corners: Array = FACE_CORNERS[face]
	var face_uvs: Array = FACE_UVS[face]
	var normal: Vector3 = FACE_NORMALS[face]
	var layer := face_layer[block_id * 6 + face]
	var shade: float = FACE_SHADE[face]
	var base_tone := Color(tint.r * shade, tint.g * shade, tint.b * shade, 1.0)
	var has_ao := ao.size() == 4
	var uv2 := Vector2(float(layer), glow)
	var top := 1.0 if face != BlockDB.FACE_NY else 0.0
	var base_index := vertices.size()
	for corner_index in 4:
		var corner: Vector3 = corners[corner_index]
		if top > 0.0 and corner.y > 0.0:
			corner.y -= 1.0 - height_offset
		vertices.append(centre + corner)
		normals.append(normal)
		uvs.append(face_uvs[corner_index])
		uv2s.append(uv2)
		if has_ao:
			var factor: float = ao[corner_index]
			colors.append(Color(base_tone.r * factor, base_tone.g * factor, base_tone.b * factor, 1.0))
		else:
			colors.append(base_tone)
	for quad_index in QUAD_INDICES:
		indices.append(base_index + quad_index)
	surface["faces"] = int(surface["faces"]) + 1


## Fills `_ao_scratch` with the four ambient-occlusion factors of one face, in
## `FACE_CORNERS` order.  Standard voxel AO: a corner is darkened by the two
## in-plane neighbours and the diagonal cell, and fully hidden corners are never
## darker than the two-sided case.
func _face_ao_into(padded_centre: int, face: int) -> void:
	var outside: int = padded_centre + int(FACE_STRIDE[face])
	var base := face * 4
	var padded := _padded
	var occluder := _occluder
	for corner_index in 4:
		var slot := base + corner_index
		var side_a := occluder[padded[outside + AO_OFFSET_A[slot]]] == 1
		var side_b := occluder[padded[outside + AO_OFFSET_B[slot]]] == 1
		var diagonal := false
		if not (side_a and side_b):
			diagonal = occluder[padded[outside + AO_OFFSET_DIAGONAL[slot]]] == 1
		var occlusion := (1 if side_a else 0) + (1 if side_b else 0) + (1 if diagonal else 0)
		_ao_scratch[corner_index] = 1.0 - AO_STRENGTH * float(occlusion)


## Deterministic, order-independent brightness multiplier for one world cell.
func _cell_variation(cell: Vector3i) -> float:
	var h: int = cell.x * 374761393 + cell.y * 668265263 + cell.z * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	var roll: int = absi(h) % 1000
	return VARIATION_MIN + float(roll) / 1000.0 * VARIATION_RANGE


## Low-frequency hue/tone variation for grass and foliage.  A 24-block lattice
## gives large soft patches (the world reads as meadows and glades rather than one
## flat green), while the per-cell term above still breaks up individual blocks.
func _macro_tint(cell: Vector3i) -> Color:
	const SCALE := 24
	var fx := float(posmod(cell.x, SCALE)) / float(SCALE)
	var fz := float(posmod(cell.z, SCALE)) / float(SCALE)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var x0 := floori(float(cell.x) / float(SCALE))
	var z0 := floori(float(cell.z) / float(SCALE))
	var a := _macro_hash(x0, z0)
	var b := _macro_hash(x0 + 1, z0)
	var c := _macro_hash(x0, z0 + 1)
	var d := _macro_hash(x0 + 1, z0 + 1)
	var value := lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)
	# Cool deep green through warm yellow-green, kept close to neutral so the
	# biome tint still decides the overall hue.
	return Color(0.90 + 0.13 * value, 0.97 + 0.05 * value, 0.90 + 0.08 * (1.0 - value))


func _macro_hash(x: int, z: int) -> float:
	var h: int = x * 668265263 + z * 374761393 + 0x51ed270b
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 1000) / 1000.0


## Water faces are emitted in chunk-local space like every other layer (the chunk
## node carries the world offset), but their UVs are derived from the *world*
## position so the animated surface tiles seamlessly across chunk borders.
## The top edge follows the fluid surface height.
func _emit_water_face(surface: Dictionary, local_centre: Vector3, world_centre: Vector3, face: int, normal: Vector3i, surface_height: float, block_id: int, world_position: Vector3i) -> void:
	var vertices: PackedVector3Array = surface["vertex"]
	var normals: PackedVector3Array = surface["normal"]
	var uvs: PackedVector2Array = surface["uv"]
	var uv2s: PackedVector2Array = surface["uv2"]
	var colors: PackedColorArray = surface["color"]
	var indices: PackedInt32Array = surface["index"]
	var corners: Array = FACE_CORNERS[face]
	var face_normal := Vector3(normal)
	var layer := face_layer[block_id * 6 + face]
	var base_index := vertices.size()
	for corner_index in 4:
		var corner: Vector3 = corners[corner_index]
		if corner.y > 0.0 and face != BlockDB.FACE_NY:
			corner.y -= 1.0 - surface_height
		vertices.append(local_centre + corner)
		normals.append(face_normal)
		var world_corner := world_centre + corner
		if face_normal.y != 0.0:
			uvs.append(Vector2(world_corner.x * 0.25, world_corner.z * 0.25))
		else:
			var horizontal := world_corner.z if face_normal.x != 0.0 else world_corner.x
			uvs.append(Vector2(horizontal * 0.25, world_corner.y * 0.25))
		uv2s.append(Vector2(float(layer), 0.0))
		# Shade water slightly darker with depth (lower surface = deeper).
		var depth_tone := 0.72 + 0.28 * surface_height
		colors.append(Color(depth_tone, depth_tone, depth_tone, 1.0))
	for quad_index in QUAD_INDICES:
		indices.append(base_index + quad_index)
	surface["faces"] = int(surface["faces"]) + 1


func _emit_collision(centre: Vector3, face: int) -> void:
	var vertices: PackedVector3Array = _collision["vertex"]
	var indices: PackedInt32Array = _collision["index"]
	var corners: Array = FACE_CORNERS[face]
	var base_index := vertices.size()
	for corner_index in 4:
		vertices.append(centre + corners[corner_index])
	for quad_index in QUAD_INDICES:
		indices.append(base_index + quad_index)


## Crossed quads for flowers, bushes, grass tufts and other non-cube decoration.
## Grass/ferns use two planes; flowers use three and bushes four so they still
## read as an object when the camera orbits them, without a mesh per plant.
func _emit_deco(block_id: int, centre: Vector3, tint: Color) -> void:
	var surface: Dictionary = _buffers[BlockDB.LAYER_DECO]
	var vertices: PackedVector3Array = surface["vertex"]
	var normals: PackedVector3Array = surface["normal"]
	var uvs: PackedVector2Array = surface["uv"]
	var uv2s: PackedVector2Array = surface["uv2"]
	var colors: PackedColorArray = surface["color"]
	var indices: PackedInt32Array = surface["index"]
	var layer := face_layer[block_id * 6 + BlockDB.FACE_PY]
	var uv2 := Vector2(float(layer), 0.0)
	var tone := Color(tint.r, tint.g, tint.b, 1.0)
	var half := 0.5 - 0.06
	if BlockDB.is_flower(block_id):
		half = 0.28
	elif block_id == BlockDB.BUSH:
		half = 0.44
	var bottom := centre + Vector3(0.0, -0.5, 0.0)
	# Crops are crossed quads too, but their height grows with the stage.  The
	# bottom stays on the farmland surface; only the top edge moves up.
	var height := BlockDB.deco_height[block_id] if block_id < BlockDB.deco_height.size() else 1.0
	var up := Vector3(0.0, height, 0.0)
	var plane_count := 2
	if block_id == BlockDB.BUSH:
		plane_count = 4
	elif BlockDB.is_flower(block_id):
		plane_count = 3
	var quad_uvs: Array = [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
	for plane_index in plane_count:
		var angle := PI * float(plane_index) / float(plane_count)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var left := bottom - direction * half
		var right := bottom + direction * half
		var plane := [left, left + up, right + up, right]
		var base_index := vertices.size()
		for corner_index in 4:
			vertices.append(plane[corner_index])
			normals.append(Vector3.UP)
			uvs.append(quad_uvs[corner_index])
			uv2s.append(uv2)
			colors.append(tone)
		for quad_index in QUAD_INDICES:
			indices.append(base_index + quad_index)
		surface["faces"] = int(surface["faces"]) + 1


## Custom one-cell models.  They are ordinary opaque geometry emitted into the
## chunk mesh (no per-block scene nodes) and stay inside the one-metre cell, so
## placement, save/load, collision and chunk streaming are unchanged.
func _emit_custom(surface: Dictionary, centre: Vector3, block_id: int, padded_centre: int) -> void:
	# A tiny lift keeps the model's bottom faces off the coplanar top face of the
	# block below it, which otherwise z-fights and reads as a translucent slab
	# underneath the model.  5 mm is invisible at gameplay distance.
	var lifted := centre + Vector3(0.0, 0.005, 0.0)
	match block_id:
		BlockDB.CRAFTING_TABLE:
			_emit_crafting_table(surface, lifted)
		BlockDB.FURNACE:
			_emit_furnace(surface, lifted)
		BlockDB.CHEST:
			_emit_chest(surface, lifted)
		BlockDB.BARREL:
			_emit_barrel(surface, lifted)
		BlockDB.LANTERN:
			_emit_lantern(surface, lifted)
		BlockDB.FENCE:
			_emit_fence(surface, lifted, padded_centre)


func _emit_crafting_table(surface: Dictionary, centre: Vector3) -> void:
	var top := library.layer_index("crafting_table_top")
	var side := library.layer_index("crafting_table_side")
	var planks := library.layer_index("planks")
	var log_side := library.layer_index("oak_log_side")
	var log_top := library.layer_index("oak_log_top")
	# Four legs, open underneath.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var x0: float = 0.30 if sx > 0 else -0.42
			var z0: float = 0.30 if sz > 0 else -0.42
			_emit_box(surface, centre, Vector3(x0, -0.5, z0), Vector3(x0 + 0.12, 0.34, z0 + 0.12),
				log_top, log_side, log_top)
	# Side aprons with the tool-rack texture.
	_emit_box(surface, centre, Vector3(-0.42, 0.06, 0.40), Vector3(0.42, 0.24, 0.48),
		planks, side, planks)
	_emit_box(surface, centre, Vector3(-0.42, 0.06, -0.48), Vector3(0.42, 0.24, -0.40),
		planks, side, planks)
	_emit_box(surface, centre, Vector3(0.40, 0.06, -0.40), Vector3(0.48, 0.24, 0.40),
		planks, side, planks)
	_emit_box(surface, centre, Vector3(-0.48, 0.06, -0.40), Vector3(-0.40, 0.24, 0.40),
		planks, side, planks)
	# Overhanging tabletop with a framed working surface.
	_emit_box(surface, centre, Vector3(-0.48, 0.30, -0.48), Vector3(0.48, 0.42, 0.48),
		top, side, planks)
	# Raised rim around the top, in dark log wood.
	_emit_box(surface, centre, Vector3(-0.48, 0.42, -0.48), Vector3(0.48, 0.46, -0.43),
		log_top, log_side, log_side)
	_emit_box(surface, centre, Vector3(-0.48, 0.42, 0.43), Vector3(0.48, 0.46, 0.48),
		log_top, log_side, log_side)
	_emit_box(surface, centre, Vector3(-0.48, 0.42, -0.43), Vector3(-0.43, 0.46, 0.43),
		log_top, log_side, log_side)
	_emit_box(surface, centre, Vector3(0.43, 0.42, -0.43), Vector3(0.48, 0.46, 0.43),
		log_top, log_side, log_side)


func _emit_furnace(surface: Dictionary, centre: Vector3) -> void:
	var masonry := library.layer_index("furnace_side")
	var cap := library.layer_index("furnace_top")
	var stone := library.layer_index("stone_brick")
	var opening := library.layer_index("furnace_opening")
	# Plinth and main body.  The +Z face of the body is omitted so the recessed
	# opening and its frame can be built in front of it.
	_emit_box(surface, centre, Vector3(-0.47, -0.5, -0.47), Vector3(0.47, -0.40, 0.47),
		stone, stone, stone)
	_emit_box(surface, centre, Vector3(-0.44, -0.40, -0.44), Vector3(0.44, 0.40, 0.44),
		cap, masonry, cap, -1, BlockDB.FACE_PZ)
	# Slightly overhanging top cap.
	_emit_box(surface, centre, Vector3(-0.47, 0.40, -0.47), Vector3(0.47, 0.47, 0.47),
		cap, stone, stone)
	# Recessed ember interior (its +Z face carries the glow flag).
	_emit_box(surface, centre, Vector3(-0.23, -0.30, 0.36), Vector3(0.23, 0.17, 0.40),
		opening, opening, opening, BlockDB.FACE_PZ)
	# Masonry frame around the opening, proud of the body.
	_emit_box(surface, centre, Vector3(-0.44, -0.30, 0.40), Vector3(-0.23, 0.17, 0.46),
		masonry, masonry, masonry)
	_emit_box(surface, centre, Vector3(0.23, -0.30, 0.40), Vector3(0.44, 0.17, 0.46),
		masonry, masonry, masonry)
	_emit_box(surface, centre, Vector3(-0.23, -0.44, 0.40), Vector3(0.23, -0.30, 0.46),
		masonry, masonry, masonry)
	_emit_box(surface, centre, Vector3(-0.23, 0.17, 0.40), Vector3(0.23, 0.40, 0.46),
		masonry, masonry, masonry)
	# Lintel above the mouth.
	_emit_box(surface, centre, Vector3(-0.31, 0.17, 0.44), Vector3(0.31, 0.25, 0.49),
		stone, stone, stone)


## A storage chest: a plank body with a lid, a dark band and a small latch.
## Custom geometry inside the cell, full-cube collision and logical identity.
func _emit_chest(surface: Dictionary, centre: Vector3) -> void:
	var planks := library.layer_index("planks")
	var band := library.layer_index("oak_log_side")
	var band_top := library.layer_index("oak_log_top")
	# Body and lid, slightly inset from the cell so the edges read clearly.
	_emit_box(surface, centre, Vector3(-0.44, -0.5, -0.38), Vector3(0.44, 0.16, 0.38),
		planks, planks, planks)
	_emit_box(surface, centre, Vector3(-0.46, 0.16, -0.40), Vector3(0.46, 0.40, 0.40),
		planks, planks, planks)
	# Dark band between body and lid, and a latch on the front face.
	_emit_box(surface, centre, Vector3(-0.46, 0.14, -0.41), Vector3(0.46, 0.18, 0.41),
		band_top, band, band_top)
	_emit_box(surface, centre, Vector3(-0.07, 0.10, 0.38), Vector3(0.07, 0.24, 0.43),
		band_top, band, band_top)
	# Small feet so the chest does not sit perfectly flush on the ground.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var x0: float = 0.36 if sx > 0 else -0.44
			var z0: float = 0.30 if sz > 0 else -0.38
			_emit_box(surface, centre, Vector3(x0, -0.5, z0), Vector3(x0 + 0.08, -0.44, z0 + 0.08),
				band_top, band, band_top)


## A barrel: staved body with two proud iron bands and a lid.  One-cell model,
## full-cube collision, ordinary block identity.
func _emit_barrel(surface: Dictionary, centre: Vector3) -> void:
	var side := library.layer_index("barrel_side")
	var top := library.layer_index("barrel_top")
	var planks := library.layer_index("planks")
	_emit_box(surface, centre, Vector3(-0.38, -0.5, -0.38), Vector3(0.38, 0.36, 0.38),
		top, side, planks)
	# Two bands sit slightly proud of the staves.
	for y in [-0.36, 0.22]:
		_emit_box(surface, centre, Vector3(-0.41, y, -0.41), Vector3(0.41, y + 0.08, 0.41),
			planks, planks, planks)
	# A slight chime/lip at the top.
	_emit_box(surface, centre, Vector3(-0.42, 0.36, -0.42), Vector3(0.42, 0.44, 0.42),
		top, planks, planks)


## A hanging lantern: dark iron cap/base, four corner posts and a warm emissive
## core.  Non-solid, so a player can walk under it; the light itself is provided
## by the bounded `LanternLights` pool, not by a node per block.
func _emit_lantern(surface: Dictionary, centre: Vector3) -> void:
	var side := library.layer_index("lantern_side")
	var cap := library.layer_index("lantern_top")
	var iron := library.layer_index("stone")
	# Thin top and bottom plates, leaving the panes visible between them.  The
	# model is deliberately smaller than a full block: a lantern is a detail hung
	# on a fence post, not a glowing crate.
	_emit_box(surface, centre, Vector3(-0.22, 0.28, -0.22), Vector3(0.22, 0.38, 0.22),
		cap, cap, cap)
	_emit_box(surface, centre, Vector3(-0.19, -0.36, -0.19), Vector3(0.19, -0.28, 0.19),
		side, side, side)
	# Four posts.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var x0: float = 0.16 if sx > 0 else -0.22
			var z0: float = 0.16 if sz > 0 else -0.22
			_emit_box(surface, centre, Vector3(x0, -0.30, z0), Vector3(x0 + 0.06, 0.30, z0 + 0.06),
				iron, iron, iron)
	# Warm core; every side face carries the emissive flag.
	_emit_box(surface, centre, Vector3(-0.17, -0.29, -0.17), Vector3(0.17, 0.29, 0.17),
		cap, side, cap, -2)
	# Hanging ring, so a lantern on a post reads as hung rather than floating.
	_emit_box(surface, centre, Vector3(-0.03, 0.38, -0.03), Vector3(0.03, 0.46, 0.03),
		iron, iron, iron)


## A fence post with rails only toward neighbouring fence blocks, so a line of
## fences connects and a standalone post does not sprout crossbars into the air.
func _emit_fence(surface: Dictionary, centre: Vector3, padded_centre: int) -> void:
	var rail := library.layer_index("fence")
	var post_side := library.layer_index("oak_log_side")
	var post_top := library.layer_index("oak_log_top")
	# Post.  The rail texture is designed for the horizontal rails only; using it
	# on a narrow post made the post read as three stacked boards.
	_emit_box(surface, centre, Vector3(-0.10, -0.5, -0.10), Vector3(0.10, 0.46, 0.10),
		post_top, post_side, post_top)
	# Post cap.
	_emit_box(surface, centre, Vector3(-0.14, 0.46, -0.14), Vector3(0.14, 0.50, 0.14),
		post_side, post_side, post_side)
	var connects_x := _is_fence_neighbour(padded_centre, BlockDB.FACE_PX) \
		or _is_fence_neighbour(padded_centre, BlockDB.FACE_NX)
	var connects_z := _is_fence_neighbour(padded_centre, BlockDB.FACE_PZ) \
		or _is_fence_neighbour(padded_centre, BlockDB.FACE_NZ)
	if connects_x:
		for y in [-0.12, 0.24]:
			_emit_box(surface, centre, Vector3(-0.5, y, -0.06), Vector3(0.5, y + 0.10, 0.06),
				rail, rail, rail)
	if connects_z:
		for y in [-0.12, 0.24]:
			_emit_box(surface, centre, Vector3(-0.06, y, -0.5), Vector3(0.06, y + 0.10, 0.5),
				rail, rail, rail)


func _is_fence_neighbour(padded_centre: int, face: int) -> bool:
	return int(_padded[padded_centre + int(FACE_STRIDE[face])]) == BlockDB.FENCE


## Adds an axis-aligned box to a surface.  Textures are mapped 0..1 per face;
## this is intentionally simple and only used for small station details.
func _emit_box(surface: Dictionary, centre: Vector3, box_min: Vector3, box_max: Vector3,
		top_layer: int, side_layer: int, bottom_layer: int,
		glow_face: int = -1, skip_face: int = -1) -> void:
	var vertices: PackedVector3Array = surface["vertex"]
	var normals: PackedVector3Array = surface["normal"]
	var uvs: PackedVector2Array = surface["uv"]
	var uv2s: PackedVector2Array = surface["uv2"]
	var colors: PackedColorArray = surface["color"]
	var indices: PackedInt32Array = surface["index"]
	for face in 6:
		if face == skip_face:
			continue
		var layer := side_layer
		if face == BlockDB.FACE_PY:
			layer = top_layer
		elif face == BlockDB.FACE_NY:
			layer = bottom_layer
		var corners: Array = FACE_CORNERS[face]
		var face_uvs: Array = FACE_UVS[face]
		var normal: Vector3 = FACE_NORMALS[face]
		var shade: float = FACE_SHADE[face]
		var tone := Color(shade, shade, shade, 1.0)
		var glow := face == glow_face or (glow_face == -2 and face != BlockDB.FACE_PY and face != BlockDB.FACE_NY)
		var uv2 := Vector2(float(layer), 1.0 if glow else 0.0)
		var base_index := vertices.size()
		for corner_index in 4:
			var unit: Vector3 = corners[corner_index]
			var corner := Vector3(
				centre.x + (box_min.x if unit.x < 0.0 else box_max.x),
				centre.y + (box_min.y if unit.y < 0.0 else box_max.y),
				centre.z + (box_min.z if unit.z < 0.0 else box_max.z)
			)
			vertices.append(corner)
			normals.append(normal)
			uvs.append(face_uvs[corner_index])
			uv2s.append(uv2)
			colors.append(tone)
		for quad_index in QUAD_INDICES:
			indices.append(base_index + quad_index)
		surface["faces"] = int(surface["faces"]) + 1


func _assemble_array_mesh(surfaces: Array, layers: Array) -> ArrayMesh:
	var mesh: ArrayMesh = null
	for layer: int in layers:
		var surface: Dictionary = surfaces[layer]
		var indices: PackedInt32Array = surface["index"]
		if indices.is_empty():
			continue
		if mesh == null:
			mesh = ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface["vertex"]
		arrays[Mesh.ARRAY_NORMAL] = surface["normal"]
		arrays[Mesh.ARRAY_TEX_UV] = surface["uv"]
		arrays[Mesh.ARRAY_TEX_UV2] = surface["uv2"]
		arrays[Mesh.ARRAY_COLOR] = surface["color"]
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.for_layer(layer))
	return mesh
