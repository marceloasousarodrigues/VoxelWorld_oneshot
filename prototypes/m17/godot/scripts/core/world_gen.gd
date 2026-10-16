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

enum Biome { OCEAN, BEACH, PLAINS, FOREST, DESERT, SAVANNA, SNOW, MOUNTAIN }

const BIOME_NAMES := ["Ocean", "Beach", "Plains", "Forest", "Desert", "Savanna", "Snow", "Mountain"]

static var BIOME_TINTS := [
	Color(0.435, 0.612, 0.447),  # ocean floor
	Color(0.643, 0.710, 0.416),  # beach
	Color(0.494, 0.769, 0.333),  # plains
	Color(0.388, 0.702, 0.290),  # forest
	Color(0.710, 0.674, 0.369),  # desert
	Color(0.702, 0.678, 0.322),  # savanna
	Color(0.624, 0.722, 0.580),  # snow
	Color(0.541, 0.659, 0.463),  # mountain
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
	var trunk := 4 + _hash2(x, z, 4242) % 3
	return {"type": TreeType.OAK, "base": ground + 1, "height": trunk, "canopy": 2 + _hash2(x, z, 555) % 2}


func _pine(x: int, z: int, ground: int) -> Dictionary:
	var trunk := 7 + _hash2(x, z, 8888) % 4
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
					elif world_y >= height - 3:
						block_id = subsurface
					elif underwater and world_y >= height - 2:
						block_id = BlockDB.CLAY if _hash3(world_x, world_y, world_z, 31) % 5 == 0 else subsurface
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
	_generate_decorations(chunk, heights, biomes, base_x, base_z, base_y)
	chunk.surface = heights.duplicate()
	chunk.generated = true
	chunk.mark_dirty()


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
	var radius := maxi(1, canopy_radius)
	for dy in range(-2, 2):
		var layer_radius := radius if dy < 0 else maxi(1, radius - 1)
		if dy == -2:
			layer_radius = radius
		for dz in range(-layer_radius, layer_radius + 1):
			for dx in range(-layer_radius, layer_radius + 1):
				if absi(dx) == layer_radius and absi(dz) == layer_radius and (dy >= 0 or layer_radius > 1):
					# Trim the corners so canopies read as rounded blobs.
					if _hash3(local_x + dx, top + dy, local_z + dz, 5) % 3 != 0:
						continue
				_place_block(chunk, local_x + dx, top + dy, local_z + dz, BlockDB.OAK_LEAVES, base_y, true)
	_place_block(chunk, local_x, top + 2, local_z, BlockDB.OAK_LEAVES, base_y, true)


func _place_pine(chunk: ChunkData, local_x: int, base: int, local_z: int, trunk: int, base_y: int) -> void:
	for offset in trunk:
		_place_block(chunk, local_x, base + offset, local_z, BlockDB.PINE_LOG, base_y, false)
	var top := base + trunk
	var radius := 3
	for offset in range(-2, 3):
		var layer := top + offset
		var level := 2 - absi(offset - 0)
		var layer_radius := clampi(radius - absi(offset + 2), 0, radius)
		if offset >= 0:
			layer_radius = maxi(0, 1 - offset + 1)
		for dz in range(-layer_radius, layer_radius + 1):
			for dx in range(-layer_radius, layer_radius + 1):
				if layer_radius > 1 and absi(dx) + absi(dz) > layer_radius + 1:
					continue
				_place_block(chunk, local_x + dx, layer, local_z + dz, BlockDB.PINE_LEAVES, base_y, true)
	_place_block(chunk, local_x, top + 3, local_z, BlockDB.PINE_LEAVES, base_y, true)


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
