class_name WorldGen
extends RefCounted

## Deterministic procedural terrain generation for the M17 Godot game.
##
## Everything is a pure function of the world seed and world coordinates, so any
## chunk can be generated at any time, in any order, on any thread, and still
## produce identical voxels.  Trees, caves and ores may span chunk borders; tree
## placement is therefore decided per *column* and each chunk only writes the
## voxels of a tree that actually fall inside it.

const WORLD_HEIGHT := 128
const CHUNKS_Y := WORLD_HEIGHT / ChunkData.SIZE
const SEA_LEVEL := 62
const BASE_HEIGHT := 66
const TREE_PAD := 3

## Structures are placed one per "region" of this many blocks, at a deterministic
## offset inside it.  `STRUCTURE_MARGIN` keeps a footprint inside its own region,
## so two structures can never overlap.
const STRUCTURE_REGION := 96
const STRUCTURE_MARGIN := 8
## Out of 1000 regions, the ones whose roll is below this get a structure.
const STRUCTURE_CHANCE := 620

enum Biome { OCEAN, BEACH, PLAINS, FOREST, DESERT, SAVANNA, SNOW, MOUNTAIN }

const BIOME_NAMES := ["Ocean", "Beach", "Plains", "Forest", "Desert", "Savanna", "Snow", "Mountain"]

## M18 tints are deliberately close to white: the graded textures now carry the
## hue, and the biome only shifts it (cooler forest, warmer savanna, paler snow)
## instead of multiplying it into neon.
static var BIOME_TINTS := [
	Color(0.866, 0.960, 0.906),  # ocean floor
	Color(0.976, 0.976, 0.882),  # beach
	Color(0.960, 0.988, 0.858),  # plains
	Color(0.872, 0.960, 0.840),  # forest
	Color(0.996, 0.964, 0.858),  # desert
	Color(0.996, 0.964, 0.836),  # savanna
	Color(0.960, 0.976, 1.000),  # snow
	Color(0.916, 0.960, 0.906),  # mountain
]

# Blocks that receive the biome tint on their mesh vertices.
const TINTED_BLOCKS := [
	BlockDB.GRASS, BlockDB.DRY_GRASS, BlockDB.OAK_LEAVES, BlockDB.PINE_LEAVES,
	BlockDB.GRASS_TUFT, BlockDB.TALL_GRASS, BlockDB.JUNGLE_GRASS, BlockDB.FERN, BlockDB.DRY_SHRUB,
]

enum TreeType { NONE, OAK, PINE, CACTUS }

var world_seed: int = 17017

var _continent: FastNoiseLite
var _hills: FastNoiseLite
var _mountain: FastNoiseLite
var _temperature: FastNoiseLite
var _humidity: FastNoiseLite
var _cave_a: FastNoiseLite
var _cave_b: FastNoiseLite
var _cavern: FastNoiseLite

var _column_cache: Dictionary = {}
var _cache_limit := 4096
var stats := {"chunks": 0, "columns": 0}


func _init(world_seed_value: int = 17017) -> void:
	world_seed = world_seed_value
	_continent = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0042, 4, 0.5)
	_hills = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.021, 3, 0.45)
	_mountain = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0026, 3, 0.5)
	_temperature = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0016, 2, 0.5)
	_humidity = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0021, 2, 0.5)
	_cave_a = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.026, 2, 0.5)
	_cave_b = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.031, 2, 0.5)
	_cavern = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.011, 3, 0.55)


func _noise(type: int, frequency: float, octaves: int, gain: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = type
	noise.seed = world_seed + int(frequency * 100000.0)
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.0
	return noise


# --- integer hashing (engine-independent determinism) ----------------------

func _hash2(x: int, z: int, salt: int) -> int:
	var h: int = x * 374761393 + z * 668265263 + (world_seed + salt) * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return abs(h)


func _hash3(x: int, y: int, z: int, salt: int) -> int:
	var h: int = x * 2654435761 + y * 40503 + z * 2246822519 + (world_seed + salt) * 668265263
	h = (h ^ (h >> 15)) * 2246822519
	h = (h ^ (h >> 13)) * 3266489917
	return abs(h ^ (h >> 16))


# --- column data ----------------------------------------------------------

## World coordinates are floor-divided into chunk coordinates here, so negative
## coordinates resolve to the same column the chunk generator would produce.
func _world_height(x: int, z: int) -> int:
	return _column(_column_chunk(x), _column_chunk(z)).heights[
		ChunkData.column_index(posmod(x, ChunkData.SIZE), posmod(z, ChunkData.SIZE))
	]


func _world_biome(x: int, z: int) -> int:
	return _column(_column_chunk(x), _column_chunk(z)).biomes[
		ChunkData.column_index(posmod(x, ChunkData.SIZE), posmod(z, ChunkData.SIZE))
	]


static func _column_chunk(value: int) -> int:
	return floori(float(value) / ChunkData.SIZE)


## Height/biome for every column of one chunk block (cached).
func _column(chunk_x: int, chunk_z: int) -> Dictionary:
	var key := Vector2i(chunk_x, chunk_z)
	var cached: Variant = _column_cache.get(key)
	if cached != null:
		return cached
	if _column_cache.size() > _cache_limit:
		_column_cache.clear()
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	heights.resize(ChunkData.COLUMNS)
	biomes.resize(ChunkData.COLUMNS)
	for local_z in ChunkData.SIZE:
		for local_x in ChunkData.SIZE:
			var x := chunk_x * ChunkData.SIZE + local_x
			var z := chunk_z * ChunkData.SIZE + local_z
			var height := _compute_height(x, z)
			var index := ChunkData.column_index(local_x, local_z)
			heights[index] = height
			biomes[index] = _compute_biome(x, z, height)
	stats["columns"] = stats["columns"] + ChunkData.COLUMNS
	var entry := {"heights": heights, "biomes": biomes}
	_column_cache[key] = entry
	return entry


func _compute_height(x: int, z: int) -> int:
	var continental: float = _continent.get_noise_2d(x, z)
	var shaped: float = signf(continental) * pow(absf(continental), 1.35)
	var height := float(BASE_HEIGHT) + shaped * 30.0 + _hills.get_noise_2d(x, z) * 5.0
	var mountain := _mountain.get_noise_2d(x, z)
	if continental > 0.06:
		var mask: float = smoothstep(0.18, 0.72, mountain)
		height += mask * mask * 48.0 * clampf(continental * 3.0, 0.0, 1.0)
	return int(clampf(roundf(height), 1.0, float(WORLD_HEIGHT - 10)))


func _compute_biome(x: int, z: int, height: int) -> int:
	if height < SEA_LEVEL - 1:
		return Biome.OCEAN
	if height <= SEA_LEVEL + 1:
		return Biome.BEACH
	if height > SEA_LEVEL + 40:
		return Biome.MOUNTAIN
	var temperature: float = _temperature.get_noise_2d(x, z)
	var humidity: float = _humidity.get_noise_2d(x, z)
	if temperature < -0.34:
		return Biome.SNOW
	if temperature > 0.30 and humidity < -0.12:
		return Biome.DESERT
	if temperature > 0.16 and humidity < 0.08:
		return Biome.SAVANNA
	if humidity > 0.12:
		return Biome.FOREST
	return Biome.PLAINS


func height_at(x: int, z: int) -> int:
	return _world_height(x, z)


func biome_at(x: int, z: int) -> int:
	return _world_biome(x, z)


func biome_name(biome: int) -> String:
	if biome >= 0 and biome < BIOME_NAMES.size():
		return BIOME_NAMES[biome]
	return "Unknown"


func biome_tint(biome: int) -> Color:
	if biome >= 0 and biome < BIOME_TINTS.size():
		return BIOME_TINTS[biome]
	return Color.WHITE


func sea_level() -> int:
	return SEA_LEVEL


# --- surface materials ----------------------------------------------------

func _surface_block(biome: int, height: int) -> int:
	match biome:
		Biome.OCEAN, Biome.BEACH:
			return BlockDB.SAND
		Biome.DESERT:
			return BlockDB.SAND
		Biome.SAVANNA:
			return BlockDB.DRY_GRASS
		Biome.SNOW:
			return BlockDB.SNOW
		Biome.MOUNTAIN:
			return BlockDB.SNOW if height > SEA_LEVEL + 46 else BlockDB.STONE
		_:
			return BlockDB.GRASS


func _subsurface_block(biome: int) -> int:
	match biome:
		Biome.OCEAN, Biome.BEACH:
			return BlockDB.SAND
		Biome.DESERT:
			return BlockDB.SANDSTONE
		Biome.MOUNTAIN:
			return BlockDB.STONE
		_:
			return BlockDB.DIRT


# --- caves and ores -------------------------------------------------------

func _is_cave(x: int, y: int, z: int, height: int) -> bool:
	if y < 3:
		return false
	var ceiling := height - 3
	if height <= SEA_LEVEL:
		# Never carve the sea floor open.
		ceiling = height - 6
	if y >= ceiling:
		return false
	var noodle_a: float = _cave_a.get_noise_3d(x, y, z)
	if absf(noodle_a) > 0.05:
		var cavern: float = _cavern.get_noise_3d(x, y, z)
		return cavern > 0.66 and y < ceiling - 4
	var noodle_b: float = _cave_b.get_noise_3d(x, y, z)
	return absf(noodle_b) < 0.11


func _ore_at(x: int, y: int, z: int) -> int:
	if y < 6 or y > 76:
		return BlockDB.AIR
	# 2x2x2 hash blobs keep ore clusters readable instead of single specks.
	var roll := _hash3(x >> 1, y >> 1, z >> 1, 7717) % 1000
	if y >= 10 and y <= 74 and roll < 6:
		return BlockDB.COAL_ORE
	if y >= 8 and y <= 54 and roll >= 6 and roll < 12:
		return BlockDB.IRON_ORE
	if y >= 6 and y <= 30 and roll >= 12 and roll < 16:
		return BlockDB.GOLD_ORE
	if y >= 6 and y <= 16 and roll >= 16 and roll < 19:
		return BlockDB.DIAMOND_ORE
	return BlockDB.AIR


# --- trees, cacti and decorations ----------------------------------------

func tree_at(x: int, z: int) -> Dictionary:
	var height := _world_height(x, z)
	var biome := _world_biome(x, z)
	if height <= SEA_LEVEL:
		return {"type": TreeType.NONE}
	var roll := _hash2(x, z, 31337) % 1000
	match biome:
		Biome.FOREST:
			if roll < 70:
				return _oak(x, z, height)
		Biome.PLAINS:
			if roll < 5:
				return _oak(x, z, height)
		Biome.SAVANNA:
			if roll < 9:
				return _oak(x, z, height)
		Biome.SNOW:
			if roll < 22:
				return _pine(x, z, height)
		Biome.MOUNTAIN:
			if height < SEA_LEVEL + 40 and roll < 18:
				return _pine(x, z, height)
		Biome.DESERT:
			if roll < 12:
				return {"type": TreeType.CACTUS, "base": height + 1, "height": 1 + _hash2(x, z, 991) % 3}
	return {"type": TreeType.NONE}


func _oak(x: int, z: int, ground: int) -> Dictionary:
	var trunk := 5 + _hash2(x, z, 4242) % 3
	return {"type": TreeType.OAK, "base": ground + 1, "height": trunk, "canopy": 2 + _hash2(x, z, 555) % 2}


func _pine(x: int, z: int, ground: int) -> Dictionary:
	var trunk := 8 + _hash2(x, z, 8888) % 4
	return {"type": TreeType.PINE, "base": ground + 1, "height": trunk}


## Decoration block for a column, or AIR. Deterministic per column.
func decoration_at(x: int, z: int, surface_height: int, surface_block: int, biome: int) -> int:
	if surface_block != BlockDB.GRASS and surface_block != BlockDB.DRY_GRASS:
		return BlockDB.AIR
	if surface_height <= SEA_LEVEL:
		return BlockDB.AIR
	var roll := _hash2(x, z, 6151) % 1000
	match biome:
		Biome.FOREST:
			if roll < 150:
				return BlockDB.GRASS_TUFT
			if roll < 195:
				return BlockDB.FERN
			if roll < 225:
				return BlockDB.JUNGLE_GRASS
			if roll < 240:
				return BlockDB.TALL_GRASS
		Biome.PLAINS:
			if roll < 110:
				return BlockDB.GRASS_TUFT
			if roll < 130:
				return BlockDB.TALL_GRASS
		Biome.SAVANNA:
			if roll < 60:
				return BlockDB.DRY_SHRUB
		Biome.SNOW:
			if roll < 40:
				return BlockDB.GRASS_TUFT
		Biome.MOUNTAIN:
			if roll < 50:
				return BlockDB.GRASS_TUFT
	return BlockDB.AIR


# --- chunk generation -----------------------------------------------------

func generate_chunk(chunk: ChunkData) -> void:
	stats["chunks"] = int(stats["chunks"]) + 1
	var coord := chunk.coord
	var base_x := coord.x * ChunkData.SIZE
	var base_y := coord.y * ChunkData.SIZE
	var base_z := coord.z * ChunkData.SIZE
	var column := _column(coord.x, coord.z)
	var heights: PackedInt32Array = column["heights"]
	var biomes: PackedByteArray = column["biomes"]
	chunk.biomes = biomes.duplicate()
	var max_height := 0
	for index in heights.size():
		if heights[index] > max_height:
			max_height = heights[index]
	# Whole chunk above the terrain (and above the tallest tree): leave it empty.
	if base_y > max_height + 14:
		chunk.surface = heights.duplicate()
		chunk.generated = true
		chunk.mark_dirty()
		return

	var blocks := chunk.blocks
	var fluid := chunk.fluid
	var sources := chunk.sources
	for local_z in ChunkData.SIZE:
		for local_x in ChunkData.SIZE:
			var column_index := ChunkData.column_index(local_x, local_z)
			var height := heights[column_index]
			var biome := biomes[column_index]
			var world_x := base_x + local_x
			var world_z := base_z + local_z
			var surface_block := _surface_block(biome, height)
			var subsurface := _subsurface_block(biome)
			var underwater := height < SEA_LEVEL
			for local_y in ChunkData.SIZE:
				var world_y := base_y + local_y
				var index := ChunkData.cell_index(local_x, local_y, local_z)
				if world_y <= height:
					var block_id := BlockDB.STONE
					if world_y == 0:
						block_id = BlockDB.BEDROCK
					elif world_y <= 3 and _hash3(world_x, world_y, world_z, 99) % 10 < 4:
						block_id = BlockDB.BEDROCK
					elif world_y == height:
						block_id = surface_block
					elif underwater and world_y >= height - 2:
						# A thin subsurface clay band in submerged columns.  This
						# branch must precede the `>= height - 3` fallback below,
						# which would otherwise shadow it and make clay unreachable.
						block_id = BlockDB.CLAY if _hash3(world_x, world_y, world_z, 31) % 5 == 0 else subsurface
					elif world_y >= height - 3:
						block_id = subsurface
					else:
						block_id = BlockDB.STONE
						var ore := _ore_at(world_x, world_y, world_z)
						if ore != BlockDB.AIR:
							block_id = ore
					if block_id != BlockDB.BEDROCK and world_y > 1 and _is_cave(world_x, world_y, world_z, height):
						block_id = BlockDB.AIR
					blocks[index] = block_id
				elif world_y <= SEA_LEVEL and underwater:
					blocks[index] = BlockDB.WATER
					fluid[index] = ChunkData.SOURCE_LEVEL
					sources[index] = 1
				else:
					blocks[index] = BlockDB.AIR

	_generate_trees(chunk)
	_generate_boulders(chunk)
	_generate_decorations(chunk, heights, biomes, base_x, base_z, base_y)
	_apply_structures(chunk)
	chunk.surface = heights.duplicate()
	chunk.generated = true
	chunk.mark_dirty()


## Plants one tree of the given kind at a world column using the same shape
## functions as normal chunk generation.  Used by the M18 visual test area (and
## available to gameplay code that wants to plant a tree at runtime).
##
## Writes directly into the affected chunks, marks them dirty, and returns the
## number of chunks touched.  It is a pure function of the seed and the column,
## so planting the same tree twice produces the same voxels.
func plant_tree(world: VoxelWorld, x: int, z: int, tree_type: int) -> int:
	var ground := _world_height(x, z)
	var tree: Dictionary
	match tree_type:
		TreeType.OAK:
			tree = _oak(x, z, ground)
		TreeType.PINE:
			tree = _pine(x, z, ground)
		TreeType.CACTUS:
			tree = {"type": TreeType.CACTUS, "base": ground + 1, "height": 1 + _hash2(x, z, 991) % 3}
		_:
			return 0
	var base := int(tree["base"])
	var min_chunk_x := floori(float(x - TREE_PAD - 1) / ChunkData.SIZE)
	var max_chunk_x := floori(float(x + TREE_PAD + 1) / ChunkData.SIZE)
	var min_chunk_z := floori(float(z - TREE_PAD - 1) / ChunkData.SIZE)
	var max_chunk_z := floori(float(z + TREE_PAD + 1) / ChunkData.SIZE)
	var min_chunk_y := floori(float(base - 2) / ChunkData.SIZE)
	var max_chunk_y := floori(float(base + 14) / ChunkData.SIZE)
	var touched := 0
	for chunk_z in range(min_chunk_z, max_chunk_z + 1):
		for chunk_x in range(min_chunk_x, max_chunk_x + 1):
			for chunk_y in range(min_chunk_y, max_chunk_y + 1):
				if chunk_y < 0 or chunk_y >= CHUNKS_Y:
					continue
				var chunk := world.get_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
				if chunk == null:
					chunk = world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
				if chunk == null:
					continue
				var base_x := chunk_x * ChunkData.SIZE
				var base_y := chunk_y * ChunkData.SIZE
				var base_z := chunk_z * ChunkData.SIZE
				match tree_type:
					TreeType.CACTUS:
						_place_single_column(chunk, x - base_x, base, z - base_z, int(tree["height"]), BlockDB.CACTUS, base_y)
					TreeType.PINE:
						_place_pine(chunk, x - base_x, base, z - base_z, int(tree["height"]), base_y)
					_:
						_place_oak(chunk, x - base_x, base, z - base_z, int(tree["height"]), int(tree["canopy"]), base_y)
				chunk.mark_dirty()
				touched += 1
	return touched


func _generate_trees(chunk: ChunkData) -> void:
	var coord := chunk.coord
	var base_x := coord.x * ChunkData.SIZE
	var base_y := coord.y * ChunkData.SIZE
	var base_z := coord.z * ChunkData.SIZE
	for local_z in range(-TREE_PAD, ChunkData.SIZE + TREE_PAD):
		for local_x in range(-TREE_PAD, ChunkData.SIZE + TREE_PAD):
			var world_x := base_x + local_x
			var world_z := base_z + local_z
			var tree := tree_at(world_x, world_z)
			var type := int(tree["type"])
			if type == TreeType.NONE:
				continue
			if type == TreeType.CACTUS:
				_place_single_column(chunk, world_x - base_x, int(tree["base"]), world_z - base_z, int(tree["height"]), BlockDB.CACTUS, base_y)
			elif type == TreeType.OAK:
				_place_oak(chunk, world_x - base_x, int(tree["base"]), world_z - base_z, int(tree["height"]), int(tree["canopy"]), base_y)
			else:
				_place_pine(chunk, world_x - base_x, int(tree["base"]), world_z - base_z, int(tree["height"]), base_y)


func _place_block(chunk: ChunkData, local_x: int, world_y: int, local_z: int, block_id: int, base_y: int, overwrite_air_only: bool) -> void:
	if local_x < 0 or local_x >= ChunkData.SIZE or local_z < 0 or local_z >= ChunkData.SIZE:
		return
	var local_y := world_y - base_y
	if local_y < 0 or local_y >= ChunkData.SIZE:
		return
	var index := ChunkData.cell_index(local_x, local_y, local_z)
	if overwrite_air_only and chunk.blocks[index] != BlockDB.AIR and chunk.blocks[index] != BlockDB.WATER:
		return
	chunk.blocks[index] = block_id
	if block_id != BlockDB.WATER:
		chunk.fluid[index] = ChunkData.NO_FLUID
		chunk.sources[index] = 0


func _place_single_column(chunk: ChunkData, local_x: int, world_y: int, local_z: int, height: int, block_id: int, base_y: int) -> void:
	for offset in height:
		_place_block(chunk, local_x, world_y + offset, local_z, block_id, base_y, false)


func _place_oak(chunk: ChunkData, local_x: int, base: int, local_z: int, trunk: int, canopy_radius: int, base_y: int) -> void:
	for offset in trunk:
		_place_block(chunk, local_x, base + offset, local_z, BlockDB.OAK_LOG, base_y, false)
	var top := base + trunk
	var radius := clampi(canopy_radius, 2, 3)
	# Rounded crown: seven layers from a narrow underside through the widest
	# middle to a narrow top, with the corners trimmed deterministically.
	var layer_radii := [1, 2, 2, 3, 3, 2, 1] if radius >= 3 else [0, 1, 1, 2, 2, 1, 0]
	for layer_index in layer_radii.size():
		var layer_radius: int = int(layer_radii[layer_index])
		var dy := layer_index - 3
		for dz in range(-layer_radius, layer_radius + 1):
			for dx in range(-layer_radius, layer_radius + 1):
				if dx * dx + dz * dz > layer_radius * layer_radius + 1:
					continue
				if absi(dx) == layer_radius and absi(dz) == layer_radius:
					# Trim only the outer corners, and not every one of them.
					if _hash3(local_x + dx, top + dy, local_z + dz, 5) % 3 != 0:
						continue
				_place_block(chunk, local_x + dx, top + dy, local_z + dz, BlockDB.OAK_LEAVES, base_y, true)
	# A short branch on each side of the upper trunk gives the silhouette a
	# recognizable oak shape instead of a single green blob.
	if trunk >= 6:
		_place_block(chunk, local_x + 1, top - 2, local_z, BlockDB.OAK_LOG, base_y, false)
		_place_block(chunk, local_x - 1, top - 1, local_z, BlockDB.OAK_LOG, base_y, false)
	_place_block(chunk, local_x, top + 2, local_z, BlockDB.OAK_LEAVES, base_y, true)


func _place_pine(chunk: ChunkData, local_x: int, base: int, local_z: int, trunk: int, base_y: int) -> void:
	for offset in trunk:
		_place_block(chunk, local_x, base + offset, local_z, BlockDB.PINE_LOG, base_y, false)
	var top := base + trunk
	# Conical tiers: wide near the base, narrowing to a point, with every other
	# layer one block smaller so the silhouette reads as a pine rather than a
	# cylinder.  The offsets give the tiers a slightly ragged edge.
	var tier_radii := [1, 1, 2, 2, 3, 3, 2, 1]
	for tier in tier_radii.size():
		var layer_radius: int = int(tier_radii[tier])
		var dy := tier - 7
		var lean := 1 if _hash3(local_x, top + dy, local_z, 909) % 5 == 0 else 0
		for dz in range(-layer_radius, layer_radius + 1):
			for dx in range(-layer_radius, layer_radius + 1):
				if layer_radius > 1 and absi(dx) + absi(dz) > layer_radius + 1:
					continue
				if absi(dx) == layer_radius and absi(dz) == layer_radius and _hash3(local_x + dx, top + dy, local_z + dz, 17) % 3 != 0:
					continue
				_place_block(chunk, local_x + dx + lean, top + dy, local_z + dz,
					BlockDB.PINE_LEAVES, base_y, true)
	_place_block(chunk, local_x, top + 1, local_z, BlockDB.PINE_LEAVES, base_y, true)
	_place_block(chunk, local_x, top + 2, local_z, BlockDB.PINE_LEAVES, base_y, true)


func _generate_decorations(chunk: ChunkData, heights: PackedInt32Array, biomes: PackedByteArray, base_x: int, base_z: int, base_y: int) -> void:
	for local_z in ChunkData.SIZE:
		for local_x in ChunkData.SIZE:
			var column_index := ChunkData.column_index(local_x, local_z)
			var height := heights[column_index]
			var world_y := height + 1
			var local_y := world_y - base_y
			if local_y < 0 or local_y >= ChunkData.SIZE:
				continue
			var index := ChunkData.cell_index(local_x, local_y, local_z)
			if chunk.blocks[index] != BlockDB.AIR:
				continue
			var biome := biomes[column_index]
			var surface_block := _surface_block(biome, height)
			if surface_block != BlockDB.GRASS and surface_block != BlockDB.DRY_GRASS:
				if biome == Biome.DESERT and _hash2(base_x + local_x, base_z + local_z, 777) % 1000 < 8:
					chunk.blocks[index] = BlockDB.CACTUS
				continue
			var deco := decoration_at(base_x + local_x, base_z + local_z, height, surface_block, biome)
			if deco != BlockDB.AIR:
				chunk.blocks[index] = deco


## Sparse boulder clusters on flat, dry land.  Anchors are deterministic columns
## and every chunk writes the part of a cluster that falls inside it, so a
## boulder crossing a chunk border is complete regardless of generation order.
func _generate_boulders(chunk: ChunkData) -> void:
	var coord := chunk.coord
	var base_x := coord.x * ChunkData.SIZE
	var base_y := coord.y * ChunkData.SIZE
	var base_z := coord.z * ChunkData.SIZE
	for local_z in range(-2, ChunkData.SIZE + 2):
		for local_x in range(-2, ChunkData.SIZE + 2):
			var world_x := base_x + local_x
			var world_z := base_z + local_z
			if _hash2(world_x, world_z, 8842) % 1000 >= 3:
				continue
			var height := _world_height(world_x, world_z)
			if height <= SEA_LEVEL:
				continue
			var biome := _world_biome(world_x, world_z)
			if biome == Biome.OCEAN or biome == Biome.BEACH or biome == Biome.DESERT:
				continue
			var surface := _surface_block(biome, height)
			if surface != BlockDB.GRASS and surface != BlockDB.DRY_GRASS and surface != BlockDB.STONE and surface != BlockDB.SNOW:
				continue
			# Flat ground only, so the cluster never hangs over a slope.
			var flat := true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if absi(_world_height(world_x + dx, world_z + dz) - height) > 1:
						flat = false
			if not flat:
				continue
			# Do not put a boulder inside a tree trunk.
			if int(tree_at(world_x, world_z)["type"]) != TreeType.NONE:
				continue
			var ore_roll := _hash2(world_x, world_z, 551) % 3
			var ore := BlockDB.COAL_ORE if ore_roll == 0 else (BlockDB.IRON_ORE if ore_roll == 1 else BlockDB.AIR)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if dx * dx + dz * dz > 2:
						continue
					var roll := _hash3(world_x + dx, height + 1, world_z + dz, 2207)
					if roll % 5 == 0:
						continue
					var block_height := 1 + roll % 2
					for dy in block_height:
						var block_id := BlockDB.STONE
						var material_roll := _hash3(world_x + dx, height + 1 + dy, world_z + dz, 91) % 6
						if material_roll == 0:
							block_id = BlockDB.MOSSY_COBBLE
						elif material_roll <= 2:
							block_id = BlockDB.COBBLESTONE
						if dy == block_height - 1 and ore != BlockDB.AIR and roll % 3 == 0:
							block_id = ore
						_place_block(chunk, world_x + dx - base_x, height + 1 + dy, world_z + dz - base_z,
							block_id, base_y, true)


# --- structures (Phase D foundation) --------------------------------------
#
# Structures are in the world, not bolted on at runtime: the generator decides
# where every structure is as a pure function of the seed and the region, and
# each chunk writes only the part of it that falls inside the chunk.  That keeps
# determinism, thread safety, cross-chunk completeness and save files identical
# to the terrain rules: nothing has to be remembered separately.

## The region a world coordinate belongs to (floor semantics for negatives).
static func structure_region_of(value: int) -> int:
	return floori(float(value) / float(STRUCTURE_REGION))


## Deterministic placement for one region: `{}` when this region holds nothing, or
## `{"id": String, "x": int, "base_y": int, "z": int, "biome": int}`.
##
## The candidates are tried in a hash-chosen order, so a kind whose biome or
## slope does not fit is replaced by another one instead of leaving the region
## empty, and the same region always yields the same structure.
func structure_placement(region: Vector2i) -> Dictionary:
	if _hash2(region.x, region.y, 8801) % 1000 >= STRUCTURE_CHANCE:
		return {}
	var offset := STRUCTURE_MARGIN
	var span := STRUCTURE_REGION - STRUCTURE_MARGIN * 2
	var anchor_x := region.x * STRUCTURE_REGION + offset + _hash2(region.x, region.y, 8802) % span
	var anchor_z := region.y * STRUCTURE_REGION + offset + _hash2(region.x, region.y, 8803) % span
	var ids: Array = StructureDB.ids()
	var count: int = ids.size()
	if count == 0:
		return {}
	var start := _hash2(region.x, region.y, 8804) % count
	for step in count:
		var id := str(ids[(start + step) % count])
		var placement := _place_structure(StructureDB.definition(id), Vector2i(anchor_x, anchor_z))
		if not placement.is_empty():
			return placement
	return {}


## Siting test for one definition at one anchor (the footprint centre).
func _place_structure(definition: Dictionary, anchor: Vector2i) -> Dictionary:
	if definition.is_empty():
		return {}
	var size := StructureDB.footprint(definition)
	var origin_x := anchor.x - (size.x - 1) / 2
	var origin_z := anchor.y - (size.z - 1) / 2
	var biome := 0
	var lowest := WORLD_HEIGHT
	var highest := 0
	for local_z in size.z:
		for local_x in size.x:
			var x := origin_x + local_x
			var z := origin_z + local_z
			if local_x == 0 and local_z == 0:
				biome = _world_biome(x, z)
			var height := _world_height(x, z)
			lowest = mini(lowest, height)
			highest = maxi(highest, height)
	if not StructureDB.allows_biome(definition, biome):
		return {}
	if highest - lowest > int(definition.get("max_slope", 0)):
		return {}
	var base_y := highest + 1
	if base_y - 1 < SEA_LEVEL + int(definition.get("min_floor_above_sea", 0)):
		return {}
	return {"id": str(definition["id"]), "x": anchor.x, "base_y": base_y, "z": anchor.y, "biome": biome}


## Writes the part of every placed structure that falls inside this chunk.  A
## structure whose anchor is in a neighbouring region but whose footprint reaches
## into this chunk is written here too, so a chunk never depends on its neighbour
## having been generated first.
func _apply_structures(chunk: ChunkData) -> void:
	var reach := StructureDB.max_extent()
	var min_x := chunk.coord.x * ChunkData.SIZE
	var min_z := chunk.coord.z * ChunkData.SIZE
	var max_x := min_x + ChunkData.SIZE - 1
	var max_z := min_z + ChunkData.SIZE - 1
	for region_z in range(structure_region_of(min_z - reach), structure_region_of(max_z + reach) + 1):
		for region_x in range(structure_region_of(min_x - reach), structure_region_of(max_x + reach) + 1):
			var placement := structure_placement(Vector2i(region_x, region_z))
			if not placement.is_empty():
				_write_structure(chunk, placement)


## Writes one placed structure's cells that land inside a chunk.
func _write_structure(chunk: ChunkData, placement: Dictionary) -> void:
	var definition := StructureDB.definition(str(placement["id"]))
	if definition.is_empty():
		return
	var size := StructureDB.footprint(definition)
	var origin_x := int(placement["x"]) - (size.x - 1) / 2
	var origin_z := int(placement["z"]) - (size.z - 1) / 2
	var base_x := chunk.coord.x * ChunkData.SIZE
	var base_y := chunk.coord.y * ChunkData.SIZE
	var base_z := chunk.coord.z * ChunkData.SIZE
	for layer: Dictionary in definition.get("layers", []):
		var world_y := int(placement["base_y"]) + int(layer["dy"])
		if world_y < base_y or world_y >= base_y + ChunkData.SIZE:
			continue
		var rows: Array = layer.get("rows", [])
		for row_index in rows.size():
			var row := str(rows[row_index])
			var world_z := origin_z + row_index
			if world_z < base_z or world_z >= base_z + ChunkData.SIZE:
				continue
			for column in row.length():
				var world_x := origin_x + column
				if world_x < base_x or world_x >= base_x + ChunkData.SIZE:
					continue
				var block_id := StructureDB.symbol_block(layer, row[column])
				if block_id == BlockDB.NO_DROP:
					continue
				var index := ChunkData.cell_index(world_x - base_x, world_y - base_y, world_z - base_z)
				# Bedrock is never carved through, so a structure can never
				# open the bottom of the world.
				if chunk.blocks[index] == BlockDB.BEDROCK:
					continue
				chunk.blocks[index] = block_id
				if block_id == BlockDB.WATER:
					chunk.fluid[index] = ChunkData.SOURCE_LEVEL
					chunk.sources[index] = 1
				else:
					chunk.fluid[index] = ChunkData.NO_FLUID
					chunk.sources[index] = 0
