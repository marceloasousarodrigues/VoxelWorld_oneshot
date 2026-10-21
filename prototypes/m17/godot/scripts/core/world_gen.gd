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
const LEGACY_VERSION := 0
## Version 1 is the M30 wilderness path; version 2 (M31) adds the denser,
## stepped canopy.  Version 3 (M32) is the playable-landscape pass: smaller
## terraces, grass-topped steps instead of brown stair treads, narrower river
## banks with mixed sand/gravel/soil, and fuller broadleaf crowns.  Versions 0, 1
## and 2 must keep producing their pinned output.
const WILDERNESS_VERSION := 2
const M32_VERSION := 3
const M33_VERSION := 4
const M34_VERSION := 5
const CURRENT_VERSION := 5
const TREE_PAD := 5
## Wide enough for a radius-4 crown with one block of lean and one of shelf offset.
const WILDERNESS_TREE_PAD := 7
## M32 crowns add a one-block per-layer shelf, so the pad grows by one.
const M32_TREE_PAD := 8
## Side length of the columns that share one canopy tree candidate (M31 forest).
const CANOPY_CELL := 2
const HIGHLAND_TERRACE_SIZE := 3
## M32 hills use natural one-block voxel steps; the M31 stepped profile is kept
## for the high mountain belt, where broad shelves read as geology rather than
## as stripes across a forested slope.
const M32_MOUNTAIN_TERRACE_SIZE := 3
## The stepped shelves now start at the snow line, so the forested upper slope
## below it uses natural one-block voxel steps.  The M31 stepped, snow-capped
## summit profile is preserved above this floor.
const M32_MOUNTAIN_FLOOR := SEA_LEVEL + 46
const RIVER_BANK_LIMIT := 0.120
## M33 vegetation ecology thresholds (version 4 only).
const M33_BROADLEAF_LIMIT := SEA_LEVEL + 30
const M33_CONIFER_LIMIT := SEA_LEVEL + 44
const M33_SNOW_TREE_LIMIT := SEA_LEVEL + 38
const M33_CLEARING_SCORE := -0.16
const M33_RIVER_CORE := 1.25
const M33_RIVER_OUTER := 1.55
## M34 grove-aware woodland thinning (version 5 only).
const M34_GROVE_PATCH := 0.34
const M34_WOODLAND_KEEP := 4

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
	Color(0.970, 1.000, 0.780),  # forest: vivid yellow-green foliage and meadows
	Color(0.996, 0.964, 0.858),  # desert
	Color(0.996, 0.964, 0.836),  # savanna
	Color(0.960, 0.976, 1.000),  # snow
	Color(0.916, 0.960, 0.906),  # mountain
]


static func is_supported_version(version: int) -> bool:
	return version >= LEGACY_VERSION and version <= CURRENT_VERSION

# Blocks that receive the biome tint on their mesh vertices.
const TINTED_BLOCKS := [
	BlockDB.GRASS, BlockDB.DRY_GRASS, BlockDB.OAK_LEAVES, BlockDB.PINE_LEAVES,
	BlockDB.BIRCH_LEAVES, BlockDB.BLOSSOM_LEAVES,
	BlockDB.GRASS_TUFT, BlockDB.TALL_GRASS, BlockDB.JUNGLE_GRASS, BlockDB.FERN, BlockDB.DRY_SHRUB,
]

enum TreeType { NONE, OAK, PINE, CACTUS, BIRCH, BLOSSOM }

var world_seed: int = 17017
var terrain_version: int = CURRENT_VERSION

var _continent: FastNoiseLite
var _hills: FastNoiseLite
var _mountain: FastNoiseLite
var _ridge: FastNoiseLite
var _valley: FastNoiseLite
var _river: FastNoiseLite
var _forest_patches: FastNoiseLite
var _flower_patches: FastNoiseLite
var _woodland: FastNoiseLite
var _detail: FastNoiseLite
var _temperature: FastNoiseLite
var _humidity: FastNoiseLite
var _cave_a: FastNoiseLite
var _cave_b: FastNoiseLite
var _cavern: FastNoiseLite

var _column_cache: Dictionary = {}
var _cache_limit := 4096
var stats := {"chunks": 0, "columns": 0}


func _init(world_seed_value: int = 17017, terrain_version_value: int = CURRENT_VERSION) -> void:
	world_seed = world_seed_value
	terrain_version = terrain_version_value
	_continent = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0042, 4, 0.5)
	_hills = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.021, 3, 0.45)
	_mountain = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0026 if terrain_version == LEGACY_VERSION else 0.0055, 3, 0.5)
	if terrain_version != LEGACY_VERSION:
		_ridge = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.009, 3, 0.52)
		_valley = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0044, 2, 0.52)
		_river = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0055, 2, 0.55)
		_forest_patches = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0095, 2, 0.55)
		_flower_patches = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.024, 2, 0.52)
		if terrain_version >= M32_VERSION:
			# Small deterministic relief that keeps the terraces from forming
			# perfectly straight treads across a whole hillside.
			_detail = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.047, 2, 0.5)
		if terrain_version >= M33_VERSION:
			# Second low-frequency field that breaks forest-patch thresholds into
			# irregular clearings and woodland instead of one contour-shaped edge.
			_woodland = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.007, 2, 0.55)
	_temperature = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0016, 2, 0.5)
	_humidity = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0021, 2, 0.5)
	_cave_a = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.026, 2, 0.5)
	_cave_b = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.031, 2, 0.5)
	_cavern = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.011, 3, 0.55)


## True for generator version 2 and later (the M31 canopy path).
func _is_wilderness() -> bool:
	return terrain_version >= WILDERNESS_VERSION


## True for generator version 3 and later (the M32 landscape pass).
func _is_m32() -> bool:
	return terrain_version >= M32_VERSION


## True for generator version 4 and later (the M33 vegetation ecology pass).
func _is_m33() -> bool:
	return terrain_version >= M33_VERSION


## True for generator version 5 and later (the M34 canopy composition pass).
func _is_m34() -> bool:
	return terrain_version >= M34_VERSION


## Horizontal reach of a tree's crown from its trunk, in blocks.  Version 0 and 1
## keep their original pads so their chunk borders are unchanged.
func _tree_pad() -> int:
	if terrain_version == LEGACY_VERSION:
		return 3
	if _is_m32():
		return M32_TREE_PAD
	if _is_wilderness():
		return WILDERNESS_TREE_PAD
	return TREE_PAD


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


## Largest height difference to the four orthogonal neighbours.  Used to decide
## whether a surface reads as a walkable meadow or a rock face.
func _column_slope(x: int, z: int, height: int) -> int:
	var slope := 0
	slope = maxi(slope, absi(_world_height(x + 1, z) - height))
	slope = maxi(slope, absi(_world_height(x - 1, z) - height))
	slope = maxi(slope, absi(_world_height(x, z + 1) - height))
	slope = maxi(slope, absi(_world_height(x, z - 1) - height))
	return slope


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
	if terrain_version == LEGACY_VERSION:
		if continental > 0.06:
			var mask: float = smoothstep(0.18, 0.72, mountain)
			height += mask * mask * 48.0 * clampf(continental * 3.0, 0.0, 1.0)
		return int(clampf(roundf(height), 1.0, float(WORLD_HEIGHT - 10)))
	if continental > 0.06:
		var peak_floor := 0.12
		var peak_span := 0.88
		if _is_wilderness():
			# M31: broader ranges with taller summits, so snowy peaks appear inside
			# the streamed area instead of only at rare noise maxima.
			peak_floor = 0.0
			peak_span = 0.6
		var peak_strength := clampf((mountain - peak_floor) / peak_span, 0.0, 1.0)
		var range_strength := clampf(continental * 3.0, 0.0, 1.0)
		# A steep curve keeps mountain summits pointed instead of saturating the
		# whole upper range into broad flat tables.
		height += pow(peak_strength, 3.0) * 58.0 * range_strength
		# A separate ridged field adds narrow spines within each broad range for a
		# layered skyline. The mask keeps isolated noise peaks out of lowland plains.
		var ridge_value: float = 1.0 - absf(_ridge.get_noise_2d(x, z))
		var ridge_mask := pow(clampf(ridge_value, 0.0, 1.0), 5.0)
		height += ridge_mask * sqrt(peak_strength) * 24.0 * range_strength
		# Broad low-frequency cuts form dry side valleys between the sharper
		# ridgelines. They stay tied to mountain ranges and leave gentle lowlands
		# and existing river channels under their original shaping rules.
		var valley_distance: float = absf(_valley.get_noise_2d(x, z))
		var valley_strength := 1.0 - smoothstep(0.015, 0.105, valley_distance)
		var highland_strength := smoothstep(SEA_LEVEL + 12.0, SEA_LEVEL + 36.0, height)
		height -= valley_strength * highland_strength * 22.0
	if _is_m32():
		# Quantisation alone produces long, ruler-straight terraces.  A ±2 block
		# deterministic detail field makes the tread edges meander and adds small
		# local ridges without turning the terrain into noise.
		height += _detail.get_noise_2d(x, z) * 2.2
	var rounded_height := int(clampf(roundf(height), 1.0, float(WORLD_HEIGHT - 10)))
	# Lowlands remain softly traversable and useful for building. Higher ground
	# resolves into deliberate terraces, giving hills and plateaus a chunkier
	# profile while keeping every step deterministic at negative coordinates.
	# Keep the river corridor on one-block steps: a floodplain that rises in
	# 2-block treads reads as a concrete-sided canal, especially from the water.
	var river_floodplain := _is_m32() and _river_distance(x, z) < RIVER_BANK_LIMIT * 1.6
	if rounded_height >= SEA_LEVEL + 8 and not river_floodplain:
		if _is_m32():
			# Hills use the detail field's natural one-block steps.  Only the
			# mountain belt keeps the deliberate wide shelves, so the same 3-block
			# stair profile no longer paints brown bands across every hillside.
			if rounded_height >= M32_MOUNTAIN_FLOOR:
				rounded_height = roundi(float(rounded_height) / M32_MOUNTAIN_TERRACE_SIZE) * M32_MOUNTAIN_TERRACE_SIZE
		else:
			rounded_height = roundi(float(rounded_height) / HIGHLAND_TERRACE_SIZE) * HIGHLAND_TERRACE_SIZE
	# A low-frequency zero-contour field creates winding, connected river beds.
	# The water system already fills below-sea-level source columns across chunks;
	# shaping the bed here preserves that source and persistence contract.
	if _is_wilderness():
		# M31: the channel centre is carved below sea level so the existing source-water
		# fill can produce water.  Whether a given reach floods is limited by the
		# elevation gate above; see the M31 report.
		if rounded_height < SEA_LEVEL + 34:
			var wild_distance: float = absf(_river.get_noise_2d(x, z))
			if wild_distance < RIVER_BANK_LIMIT:
				var wild_strength := 1.0 - smoothstep(0.0, RIVER_BANK_LIMIT, wild_distance)
				var wild_floor := SEA_LEVEL - (2.0 + wild_strength * 5.0)
				rounded_height = mini(rounded_height, roundi(lerpf(float(rounded_height), wild_floor, wild_strength)))
		return clampi(rounded_height, 1, WORLD_HEIGHT - 10)
	if rounded_height > SEA_LEVEL + 1 and rounded_height < SEA_LEVEL + 34:
		var river_distance: float = absf(_river.get_noise_2d(x, z))
		if river_distance < RIVER_BANK_LIMIT:
			var river_strength := 1.0 - smoothstep(0.012, RIVER_BANK_LIMIT, river_distance)
			var river_floor := SEA_LEVEL - (2.0 + river_strength * 5.0)
			rounded_height = mini(rounded_height, roundi(lerpf(float(rounded_height), river_floor, river_strength)))
	return clampi(rounded_height, 1, WORLD_HEIGHT - 10)


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
	if _is_m32() and height > SEA_LEVEL + 8 and height <= SEA_LEVEL + 40:
		# The reference landscape is forested up its hillsides, with meadows kept
		# on the low ground.  M31 left highland plains bare, exposing long rows of
		# terrace faces; v3 closes that canopy over the hills.
		return Biome.FOREST
	if temperature > 0.30 and humidity < -0.12:
		return Biome.DESERT
	if temperature > 0.16 and humidity < 0.08:
		return Biome.SAVANNA
	if humidity > 0.12:
		return Biome.FOREST
	return Biome.PLAINS


func _river_distance(x: int, z: int) -> float:
	return absf(_river.get_noise_2d(x, z))


func height_at(x: int, z: int) -> int:
	return _world_height(x, z)


func biome_at(x: int, z: int) -> int:
	return _world_biome(x, z)


func biome_name(biome: int) -> String:
	if biome >= 0 and biome < BIOME_NAMES.size():
		return BIOME_NAMES[biome]
	return "Unknown"


## Version-aware terrain tint.  Kept static so the mesher can call it with the
## chunk's recorded generator version without knowing the world or generator.
static func tint_for_version(version: int, biome: int) -> Color:
	if version >= M32_VERSION and biome == Biome.FOREST:
		# The reference canopy is a vivid lime green rather than the darker
		# blue-green of the M31 forest.  The texture already carries the leaf
		# detail, so this only lifts the hue and keeps shaded faces readable.
		return Color(1.080, 1.100, 0.740)
	if biome >= 0 and biome < BIOME_TINTS.size():
		return BIOME_TINTS[biome]
	return Color.WHITE


func biome_tint(biome: int) -> Color:
	# Keep the historical M29 helper value for callers that ask the generator
	# directly.  The mesher uses `tint_for_version` and therefore keeps the
	# pre-M32 mesh palette for v0/v1/v2.
	if terrain_version == LEGACY_VERSION and biome == Biome.FOREST:
		return Color(0.872, 0.960, 0.840)
	return tint_for_version(terrain_version, biome)


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
			if height > SEA_LEVEL + 46:
				return BlockDB.SNOW
			# M32 keeps a green treeline on the upper slope; the bare stone belt
			# was the source of the long grey/brown bands in the M31 captures.
			return BlockDB.GRASS if _is_m32() else BlockDB.STONE
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
	if _is_m33():
		return _biome_tree_v4(x, z, height, biome)
	if _is_wilderness() and biome == Biome.FOREST:
		return _forest_canopy_tree(x, z, height)
	var roll := _hash2(x, z, 31337) % 1000
	match biome:
		Biome.FOREST:
			if terrain_version == LEGACY_VERSION:
				if roll < 8:
					return _birch(x, z, height)
				if roll < 11:
					return _blossom(x, z, height)
				if roll < 70:
					return _oak(x, z, height)
				return {"type": TreeType.NONE}
			var patch: float = _forest_patches.get_noise_2d(x, z)
			var river_distance := _river_distance(x, z)
			# Keep a broken, meadow-like ribbon along rivers so water and banks
			# remain visible through otherwise dense forest.
			if river_distance < RIVER_BANK_LIMIT * 1.25:
				return {"type": TreeType.NONE}
			# Negative patches create larger openings, the transition band thins
			# toward meadow, and positive patches gather mixed species into groves.
			if patch < -0.24:
				return {"type": TreeType.NONE}
			if patch < 0.02:
				if roll < 20:
					return _birch(x, z, height)
				if roll < 38:
					return _blossom(x, z, height)
				if roll < 58:
					return _oak(x, z, height)
			elif patch > 0.34:
				if roll < 55:
					return _birch(x, z, height)
				if roll < 110:
					return _blossom(x, z, height)
				if roll < 180:
					return _pine(x, z, height)
				if roll < 260:
					return _oak(x, z, height)
				return {"type": TreeType.NONE}
			if roll < 24:
				return _birch(x, z, height)
			if roll < 42:
				return _blossom(x, z, height)
			if roll < 52:
				return _pine(x, z, height)
			if roll < 88:
				return _oak(x, z, height)
		Biome.PLAINS:
			if roll < 4:
				return _oak(x, z, height)
			if roll < 5:
				return _birch(x, z, height)
		Biome.SAVANNA:
			if roll < 9:
				return _oak(x, z, height)
		Biome.SNOW:
			if roll < 22:
				return _pine(x, z, height)
		Biome.MOUNTAIN:
			if _is_m32() and height < SEA_LEVEL + 46:
				# A sparse-to-moderate conifer treeline below the snow cap.
				if roll < 90:
					return _pine(x, z, height)
			elif height < SEA_LEVEL + 40 and roll < 18:
				return _pine(x, z, height)
		Biome.DESERT:
			if roll < 12:
				return {"type": TreeType.CACTUS, "base": height + 1, "height": 1 + _hash2(x, z, 991) % 3}
	return {"type": TreeType.NONE}


## M33 two-scale density field.  The forest patch gives broad forest regions; the
## slower woodland field bends their boundaries into irregular clearings.
func _vegetation_score(x: int, z: int) -> float:
	# The small positive bias keeps real woodland/forest above the clearing
	# threshold while still leaving roughly a fifth of the forest open.
	return 0.68 * _forest_patches.get_noise_2d(x, z) + 0.32 * _woodland.get_noise_2d(x, z) + 0.04


## Elevation multiplier applied to the 0.95 forest candidate probability.
func _elevation_factor(height: int, broadleaf: bool) -> float:
	var delta := height - SEA_LEVEL
	if broadleaf:
		if delta <= 18:
			return 1.0
		if delta <= 24:
			return lerpf(1.0, 0.55, float(delta - 18) / 6.0)
		if delta <= 27:
			return lerpf(0.55, 0.15, float(delta - 24) / 3.0)
		if delta <= 30:
			return lerpf(0.15, 0.0, float(delta - 27) / 3.0)
		return 0.0
	if delta <= 18:
		return 1.0
	if delta <= 24:
		return lerpf(1.0, 0.80, float(delta - 18) / 6.0)
	if delta <= 27:
		return lerpf(0.80, 0.45, float(delta - 24) / 3.0)
	if delta <= 30:
		return lerpf(0.45, 0.25, float(delta - 27) / 3.0)
	if delta <= 40:
		return lerpf(0.25, 0.08, float(delta - 30) / 10.0)
	if delta <= 44:
		return lerpf(0.06, 0.02, float(delta - 40) / 4.0)
	return 0.0


func _slope_factor(slope: int, broadleaf: bool) -> float:
	var band := clampi(slope, 0, 4)
	if broadleaf:
		return [1.0, 1.0, 0.65, 0.15, 0.0][band]
	return [1.0, 1.0, 0.80, 0.40, 0.05][band]


## Candidate probability for a v4 forest tree.  A candidate is chosen once per
## 2x2 cell, so expected column coverage is roughly this value / 4.
func _v4_tree_density(height: int, slope: int, broadleaf: bool, score: float) -> float:
	if broadleaf and (height > M33_BROADLEAF_LIMIT or slope >= 4):
		return 0.0
	if not broadleaf and height > M33_CONIFER_LIMIT:
		return 0.0
	var base := smoothstep(M33_CLEARING_SCORE, -0.06, score)
	return base * _elevation_factor(height, broadleaf) * _slope_factor(slope, broadleaf)


## Broadleaf share of the candidate pool.  It fades out completely by SEA+30.
func _v4_broadleaf_share(height: int, patch: float) -> float:
	var delta := height - SEA_LEVEL
	var share := 0.80
	if delta > 18:
		share = lerpf(0.80, 0.0, clampf(float(delta - 18) / 12.0, 0.0, 1.0))
	if patch > 0.34:
		share -= 0.10
	elif patch < 0.02:
		share += 0.05
	return clampf(share, 0.0, 1.0)


func _forest_canopy_tree_v4(x: int, z: int, height: int) -> Dictionary:
	var cell_x := floori(float(x) / CANOPY_CELL)
	var cell_z := floori(float(z) / CANOPY_CELL)
	var candidate_x := cell_x * CANOPY_CELL + _hash2(cell_x, cell_z, 4711) % CANOPY_CELL
	var candidate_z := cell_z * CANOPY_CELL + _hash2(cell_x, cell_z, 4712) % CANOPY_CELL
	if x != candidate_x or z != candidate_z:
		return {"type": TreeType.NONE}
	var river_distance := _river_distance(x, z)
	if river_distance < RIVER_BANK_LIMIT * M33_RIVER_CORE:
		return {"type": TreeType.NONE}
	var river_outer := river_distance < RIVER_BANK_LIMIT * M33_RIVER_OUTER
	var score := _vegetation_score(x, z)
	if score < M33_CLEARING_SCORE:
		return {"type": TreeType.NONE}
	var patch := _forest_patches.get_noise_2d(x, z)
	var slope := _column_slope(x, z, height)
	var species_roll := _hash2(x, z, 4714) % 100
	var broadleaf := float(species_roll) < _v4_broadleaf_share(height, patch) * 100.0
	if broadleaf and (height > M33_BROADLEAF_LIMIT or slope >= 4):
		broadleaf = false
	var density := _v4_tree_density(height, slope, broadleaf, score)
	if river_outer:
		if slope > 1:
			return {"type": TreeType.NONE}
		density *= 0.25
	if density <= 0.0:
		return {"type": TreeType.NONE}
	if _hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
		return {"type": TreeType.NONE}
	if broadleaf:
		var leaf_roll := _hash2(x, z, 4715) % 100
		if leaf_roll < 75:
			return _oak(x, z, height)
		if leaf_roll < 95:
			return _birch(x, z, height)
		return _blossom(x, z, height)
	return _pine(x, z, height)


## M34 forest path.  It keeps the v4 candidate/river/score/slope/species/density
## rules and adds a deterministic woodland thinning: dense groves keep every
## candidate, open woodland keeps four of nine.
func _forest_canopy_tree_v5(x: int, z: int, height: int) -> Dictionary:
	var cell_x := floori(float(x) / CANOPY_CELL)
	var cell_z := floori(float(z) / CANOPY_CELL)
	var candidate_x := cell_x * CANOPY_CELL + _hash2(cell_x, cell_z, 4711) % CANOPY_CELL
	var candidate_z := cell_z * CANOPY_CELL + _hash2(cell_x, cell_z, 4712) % CANOPY_CELL
	if x != candidate_x or z != candidate_z:
		return {"type": TreeType.NONE}
	var patch := _forest_patches.get_noise_2d(x, z)
	if patch <= M34_GROVE_PATCH \
			and _hash2(cell_x, cell_z, 9101) % 9 >= M34_WOODLAND_KEEP:
		return {"type": TreeType.NONE}
	var river_distance := _river_distance(x, z)
	if river_distance < RIVER_BANK_LIMIT * M33_RIVER_CORE:
		return {"type": TreeType.NONE}
	var river_outer := river_distance < RIVER_BANK_LIMIT * M33_RIVER_OUTER
	var score := _vegetation_score(x, z)
	if score < M33_CLEARING_SCORE:
		return {"type": TreeType.NONE}
	var slope := _column_slope(x, z, height)
	var species_roll := _hash2(x, z, 4714) % 100
	var broadleaf := float(species_roll) < _v4_broadleaf_share(height, patch) * 100.0
	if broadleaf and (height > M33_BROADLEAF_LIMIT or slope >= 4):
		broadleaf = false
	var density := _v4_tree_density(height, slope, broadleaf, score)
	if river_outer:
		if slope > 1:
			return {"type": TreeType.NONE}
		density *= 0.25
	if density <= 0.0:
		return {"type": TreeType.NONE}
	if _hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
		return {"type": TreeType.NONE}
	if broadleaf:
		var leaf_roll := _hash2(x, z, 4715) % 100
		if leaf_roll < 75:
			return _oak(x, z, height)
		if leaf_roll < 95:
			return _birch(x, z, height)
		return _blossom(x, z, height)
	return _pine(x, z, height)


## Non-forest v4 vegetation.  Grassland and savanna keep clumped, sparse trees;
## snow and mountain use a low pine cap below their treeline.
func _biome_tree_v4(x: int, z: int, height: int, biome: int) -> Dictionary:
	if height <= SEA_LEVEL:
		return {"type": TreeType.NONE}
	if biome == Biome.FOREST:
		if _is_m34():
			return _forest_canopy_tree_v5(x, z, height)
		return _forest_canopy_tree_v4(x, z, height)
	var river_distance := _river_distance(x, z)
	if river_distance < RIVER_BANK_LIMIT * M33_RIVER_CORE:
		return {"type": TreeType.NONE}
	var river_outer := river_distance < RIVER_BANK_LIMIT * M33_RIVER_OUTER
	var roll := _hash2(x, z, 31337) % 1000
	# Highest non-forest tree chance is 1.5%; skip the slope computation for the
	# other 98.5% of columns.
	if roll >= 15:
		return {"type": TreeType.NONE}
	var slope := _column_slope(x, z, height)
	if river_outer and slope > 1:
		return {"type": TreeType.NONE}
	if river_outer and _hash2(x, z, 771) % 4 != 0:
		return {"type": TreeType.NONE}
	var score := _vegetation_score(x, z)
	match biome:
		Biome.PLAINS:
			if height <= SEA_LEVEL + 18 and slope <= 1 and roll < 8 and score > -0.10:
				return _oak(x, z, height) if roll % 3 != 0 else _birch(x, z, height)
		Biome.SAVANNA:
			if height <= SEA_LEVEL + 20 and slope <= 1 and roll < 15 and score > -0.10:
				return _oak(x, z, height)
		Biome.SNOW:
			if height < M33_SNOW_TREE_LIMIT and slope <= 2 and roll < 6:
				return _pine(x, z, height)
		Biome.MOUNTAIN:
			if height < M33_CONIFER_LIMIT and slope <= 2 and roll < 6:
				return _pine(x, z, height)
		Biome.DESERT:
			if slope <= 1 and roll < 12:
				return {"type": TreeType.CACTUS, "base": height + 1, "height": 1 + _hash2(x, z, 991) % 3}
	return {"type": TreeType.NONE}


## Version 2 forest canopy.  Each CANOPY_CELL x CANOPY_CELL block of columns has
## one hashed candidate column, so trunks keep natural spacing without a visible
## grid while the crowns knit into a continuous canopy.  Clearings and river
## corridors stay open; grove patches are denser and pine-heavy.
func _forest_canopy_tree(x: int, z: int, height: int) -> Dictionary:
	var cell_x := floori(float(x) / CANOPY_CELL)
	var cell_z := floori(float(z) / CANOPY_CELL)
	var candidate_x := cell_x * CANOPY_CELL + _hash2(cell_x, cell_z, 4711) % CANOPY_CELL
	var candidate_z := cell_z * CANOPY_CELL + _hash2(cell_x, cell_z, 4712) % CANOPY_CELL
	if x != candidate_x or z != candidate_z:
		return {"type": TreeType.NONE}
	var river_clearance := RIVER_BANK_LIMIT * (1.55 if _is_m32() else 1.25)
	if _river_distance(x, z) < river_clearance:
		return {"type": TreeType.NONE}
	var patch: float = _forest_patches.get_noise_2d(x, z)
	var clearing_threshold := -0.32 if _is_m32() else -0.24
	if patch < clearing_threshold:
		return {"type": TreeType.NONE}
	var density := 0.95
	if patch < 0.02:
		density = 0.7
	if _is_m32():
		# Larger crowns cost more faces than extra trunks, so the candidate rate
		# stays high but the species mix favours broadleaves.  Measured coverage
		# with 0.90/0.62 fell to 11.7%; 0.98/0.78 restores the M31 density band
		# without bringing back the thin pole-like silhouettes.
		density = 0.98 if patch >= 0.02 else 0.78
	if _hash2(x, z, 4713) % 1000 >= int(density * 1000.0):
		return {"type": TreeType.NONE}
	# Blossom stays rare: its pink speckle reads as noise at distance, while the
	# Image 1 canopy is a continuous lime green.
	var species := _hash2(x, z, 4714) % 100
	var tree: Dictionary
	if _is_m32():
		# Broadleaf-dominant mix.  Pines are kept for ridgelines and groves, not
		# scattered through the lowland as narrow bottle-brush silhouettes.
		if patch > 0.34:
			if species < 50:
				tree = _oak(x, z, height)
			elif species < 66:
				tree = _birch(x, z, height)
			elif species < 96:
				tree = _pine(x, z, height)
			else:
				tree = _blossom(x, z, height)
		elif species < 62:
			tree = _oak(x, z, height)
		elif species < 78:
			tree = _birch(x, z, height)
		elif species < 96:
			tree = _pine(x, z, height)
		else:
			tree = _blossom(x, z, height)
		# On a terraced hillside the uphill half of a normal crown is buried in
		# the slope.  Lifting broadleaf slope trees by up to two blocks keeps the
		# canopy above the tread and makes the forest read on hills, not only on
		# flats.  Pines are already tall and keep their natural height.
		var slope := _column_slope(x, z, height)
		if slope >= 2 and int(tree["type"]) != TreeType.PINE:
			tree["height"] = int(tree["height"]) + mini(2, slope)
		return tree
	if patch > 0.34:
		if species < 30:
			return _oak(x, z, height)
		if species < 70:
			return _pine(x, z, height)
		if species < 95:
			return _birch(x, z, height)
		return _blossom(x, z, height)
	if species < 45:
		return _oak(x, z, height)
	if species < 75:
		return _pine(x, z, height)
	if species < 95:
		return _birch(x, z, height)
	return _blossom(x, z, height)


func _oak(x: int, z: int, ground: int) -> Dictionary:
	var trunk := 5 + _hash2(x, z, 4242) % 3
	var canopy := 2 + _hash2(x, z, 555) % (2 if terrain_version == LEGACY_VERSION else 3)
	if _is_m32():
		# Broader crowns on a varied trunk: the crown mass dominates the
		# silhouette instead of a bare pole, and neighbouring trees sit at
		# different heights so the forest does not become a flat canopy carpet.
		trunk = 5 + _hash2(x, z, 4242) % 4 + _hash2(x, z, 4243) % 3
		canopy = 3 + _hash2(x, z, 555) % 2
	if _is_m33():
		var delta := ground - SEA_LEVEL
		if delta > 24:
			canopy = 2
		elif delta > 18:
			canopy = maxi(2, canopy - 1)
	return {"type": TreeType.OAK, "base": ground + 1, "height": trunk, "canopy": canopy}


func _birch(x: int, z: int, ground: int) -> Dictionary:
	# Taller and slimmer than an oak, with a lighter, airier crown.
	var trunk := 6 + _hash2(x, z, 4455) % 3
	var canopy := 2 if terrain_version == LEGACY_VERSION else 2 + _hash2(x, z, 556) % 2
	if _is_m32():
		canopy = 3
	if _is_m33():
		var delta := ground - SEA_LEVEL
		if delta > 24:
			canopy = 2
		elif delta > 18:
			canopy = maxi(2, canopy - 1)
	return {"type": TreeType.BIRCH, "base": ground + 1, "height": trunk, "canopy": canopy}


func _blossom(x: int, z: int, ground: int) -> Dictionary:
	var trunk := 5 + _hash2(x, z, 4666) % 2
	var canopy := 3 if terrain_version == LEGACY_VERSION else 3 + _hash2(x, z, 557) % 2
	if _is_m33():
		var delta := ground - SEA_LEVEL
		if delta > 24:
			canopy = 2
		elif delta > 18:
			canopy = maxi(2, canopy - 1)
	return {"type": TreeType.BLOSSOM, "base": ground + 1, "height": trunk, "canopy": canopy}


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
	if _is_m33() and surface_height > SEA_LEVEL + 30:
		if surface_height > SEA_LEVEL + 40 or roll % 4 != 0:
			return BlockDB.AIR
	match biome:
		Biome.FOREST:
			if terrain_version == LEGACY_VERSION:
				if roll < 190:
					return BlockDB.GRASS_TUFT
				if roll < 232:
					return BlockDB.FERN
				if roll < 254:
					return BlockDB.JUNGLE_GRASS
				if roll < 272:
					return BlockDB.TALL_GRASS
				if roll < 282:
					return BlockDB.BUSH
				if roll < 290:
					return BlockDB.FLOWER_RED
				if roll < 297:
					return BlockDB.FLOWER_YELLOW
				if roll < 304:
					return BlockDB.FLOWER_BLUE
				return BlockDB.AIR
			var forest_patch: float = _forest_patches.get_noise_2d(x, z)
			var river_distance := _river_distance(x, z)
			var clearing_threshold := -0.32 if _is_m32() else -0.24
			var clearing := forest_patch < clearing_threshold or river_distance < RIVER_BANK_LIMIT * 1.25
			if _is_m33():
				clearing = _vegetation_score(x, z) < M33_CLEARING_SCORE \
					or river_distance < RIVER_BANK_LIMIT * M33_RIVER_CORE
			var flower_patch: float = _flower_patches.get_noise_2d(x, z)
			if clearing and flower_patch > 0.10:
				if roll < 120:
					return BlockDB.FLOWER_RED
				if roll < 230:
					return BlockDB.FLOWER_YELLOW
				if roll < 310:
					return BlockDB.FLOWER_BLUE
				if roll < 440:
					return BlockDB.TALL_GRASS
			if roll < 205:
				return BlockDB.GRASS_TUFT
			if roll < 252:
				return BlockDB.FERN
			if roll < 267:
				return BlockDB.JUNGLE_GRASS
			if roll < 292:
				return BlockDB.TALL_GRASS
			if roll < 316:
				return BlockDB.BUSH
			if roll < 336:
				return BlockDB.FLOWER_RED
			if roll < 352:
				return BlockDB.FLOWER_YELLOW
			if roll < 368:
				return BlockDB.FLOWER_BLUE
		Biome.PLAINS:
			if roll < 150:
				return BlockDB.GRASS_TUFT
			if roll < 170:
				return BlockDB.TALL_GRASS
			if roll < 182:
				return BlockDB.BUSH
			if roll < 190:
				return BlockDB.FLOWER_RED
			if roll < 198:
				return BlockDB.FLOWER_YELLOW
			if roll < 206:
				return BlockDB.FLOWER_BLUE
		Biome.SAVANNA:
			if roll < 55:
				return BlockDB.DRY_SHRUB
			if roll < 62:
				return BlockDB.FLOWER_YELLOW
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
	chunk.terrain_version = terrain_version
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
	# M32 crowns reach seven blocks above the trunk top, so the upper margin grows
	# with them; versions 0-2 keep their historical early exit.
	if base_y > max_height + (21 if _is_m32() else 14):
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
			var river_bank := false
			var bank_subsurface := -1
			if terrain_version != LEGACY_VERSION:
				var river_distance := _river_distance(world_x, world_z)
				if _is_m32():
					# M32 banks are a narrow wet sand/gravel edge followed by a
					# mixed soil, gravel and grass transition.  M31 painted the
					# whole low bank sand, which read as a white concrete apron.
					if height > SEA_LEVEL and height <= SEA_LEVEL + 5 \
							and river_distance < RIVER_BANK_LIMIT * 1.25:
						river_bank = true
						var bank_roll := _hash3(world_x, height, world_z, 4321) % 10
						if height <= SEA_LEVEL + 1:
							surface_block = BlockDB.SAND
							bank_subsurface = BlockDB.SAND
						elif height <= SEA_LEVEL + 3 and river_distance < RIVER_BANK_LIMIT * 0.55:
							surface_block = BlockDB.SAND if bank_roll < 7 else BlockDB.GRAVEL
							bank_subsurface = surface_block
						else:
							# A mostly grassy lip with gravel bars and a little
							# exposed soil.  M31's all-sand apron and an earlier
							# all-dirt pass both read as a single flat material.
							if bank_roll < 3:
								surface_block = BlockDB.GRAVEL
							elif bank_roll < 4:
								surface_block = BlockDB.DIRT
							else:
								surface_block = BlockDB.GRASS
							bank_subsurface = BlockDB.DIRT if surface_block == BlockDB.GRASS else surface_block
				else:
					river_bank = height > SEA_LEVEL and height <= SEA_LEVEL + 5 \
						and river_distance < RIVER_BANK_LIMIT * 1.9
					if river_bank:
						surface_block = BlockDB.SAND
						bank_subsurface = BlockDB.SAND
			# Steep terrain exposes rock instead of a green carpet draped down a
			# cliff.  This is the layered / rocky silhouette the visual direction
			# asks for, and it removes the harsh grass-side striping on mountains.
			if height > SEA_LEVEL + 2:
				var slope := _column_slope(world_x, world_z, height)
				if _is_m32():
					# M32 keeps the grass top on natural hill steps and on the
					# mountain shelves.  The grass block's own side texture
					# supplies the earth band, so slopes read as green steps
					# instead of brown stair treads.
					# Only genuine cliff faces (two terrace steps or more) turn to
					# rock; a small hashed subset of the steepest grass gives
					# outcrops without painting horizontal grey bands across hills.
					if slope >= 6:
						surface_block = BlockDB.STONE
					elif slope >= 5 and surface_block == BlockDB.GRASS \
							and _hash3(world_x, height, world_z, 611) % 100 < 30:
						surface_block = BlockDB.STONE
				else:
					if slope >= 3:
						surface_block = BlockDB.STONE
					elif slope >= 2 and (surface_block == BlockDB.GRASS or surface_block == BlockDB.DRY_GRASS):
						# A hillside face reads as earth, not as a stack of green
						# ribbons; the grass top stays on the walkable steps.
						surface_block = BlockDB.DIRT
			var subsurface := bank_subsurface if river_bank else _subsurface_block(biome)
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
						# A thin subsurface band of clay and gravel in submerged
						# columns.  Clay feeds bricks and roof tiles; gravel feeds
						# packed paths.  Both must have a real world source or
						# those recipes are unreachable (M24).  This branch must
						# precede the `>= height - 3` fallback below, which would
						# otherwise shadow it.
						var shoreline_roll := _hash3(world_x, world_y, world_z, 31) % 5
						if shoreline_roll == 0:
							block_id = BlockDB.CLAY
						elif shoreline_roll == 1:
							block_id = BlockDB.GRAVEL
						else:
							block_id = subsurface
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
	if terrain_version != LEGACY_VERSION:
		_generate_fallen_logs(chunk)
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
func plant_tree(world: VoxelWorld, x: int, z: int, tree_type: int, ground_y: int = -1) -> int:
	var ground := ground_y if ground_y >= 0 else _world_height(x, z)
	var tree: Dictionary
	match tree_type:
		TreeType.OAK:
			tree = _oak(x, z, ground)
		TreeType.BIRCH:
			tree = _birch(x, z, ground)
		TreeType.BLOSSOM:
			tree = _blossom(x, z, ground)
		TreeType.PINE:
			tree = _pine(x, z, ground)
		TreeType.CACTUS:
			tree = {"type": TreeType.CACTUS, "base": ground + 1, "height": 1 + _hash2(x, z, 991) % 3}
		_:
			return 0
	var base := int(tree["base"])
	var tree_pad := _tree_pad()
	var min_chunk_x := floori(float(x - tree_pad - 1) / ChunkData.SIZE)
	var max_chunk_x := floori(float(x + tree_pad + 1) / ChunkData.SIZE)
	var min_chunk_z := floori(float(z - tree_pad - 1) / ChunkData.SIZE)
	var max_chunk_z := floori(float(z + tree_pad + 1) / ChunkData.SIZE)
	var min_chunk_y := floori(float(base - 2) / ChunkData.SIZE)
	var max_chunk_y := floori(float(base + (21 if _is_m32() else 14)) / ChunkData.SIZE)
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
					TreeType.BIRCH:
						_place_birch(chunk, x - base_x, base, z - base_z, int(tree["height"]), int(tree["canopy"]), base_y)
					TreeType.BLOSSOM:
						_place_blossom(chunk, x - base_x, base, z - base_z, int(tree["height"]), int(tree["canopy"]), base_y)
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
	var tree_pad := _tree_pad()
	for local_z in range(-tree_pad, ChunkData.SIZE + tree_pad):
		for local_x in range(-tree_pad, ChunkData.SIZE + tree_pad):
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
			elif type == TreeType.BIRCH:
				_place_birch(chunk, world_x - base_x, int(tree["base"]), world_z - base_z, int(tree["height"]), int(tree["canopy"]), base_y)
			elif type == TreeType.BLOSSOM:
				_place_blossom(chunk, world_x - base_x, int(tree["base"]), world_z - base_z, int(tree["height"]), int(tree["canopy"]), base_y)
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
	_place_broadleaf(chunk, local_x, base, local_z, trunk, canopy_radius, base_y,
		BlockDB.OAK_LOG, BlockDB.OAK_LEAVES)


func _place_birch(chunk: ChunkData, local_x: int, base: int, local_z: int, trunk: int, canopy_radius: int, base_y: int) -> void:
	_place_broadleaf(chunk, local_x, base, local_z, trunk, canopy_radius, base_y,
		BlockDB.BIRCH_LOG, BlockDB.BIRCH_LEAVES)


func _place_blossom(chunk: ChunkData, local_x: int, base: int, local_z: int, trunk: int, canopy_radius: int, base_y: int) -> void:
	_place_broadleaf(chunk, local_x, base, local_z, trunk, canopy_radius, base_y,
		BlockDB.OAK_LOG, BlockDB.BLOSSOM_LEAVES)


func _place_broadleaf(chunk: ChunkData, local_x: int, base: int, local_z: int, trunk: int,
		canopy_radius: int, base_y: int, log_block: int, leaf_block: int) -> void:
	for offset in trunk:
		_place_block(chunk, local_x, base + offset, local_z, log_block, base_y, false)
	var top := base + trunk
	var radius := clampi(canopy_radius, 2, 3 if terrain_version == LEGACY_VERSION else 4)
	var tree_world_x := chunk.coord.x * ChunkData.SIZE + local_x
	var tree_world_z := chunk.coord.z * ChunkData.SIZE + local_z
	# Per-tree lean and a ragged outline so a forest reads as varied trees rather
	# than a field of identical domes.  The lean stays inside the TREE_PAD.
	var hash_x := local_x if terrain_version == LEGACY_VERSION else tree_world_x
	var hash_z := local_z if terrain_version == LEGACY_VERSION else tree_world_z
	var lean_x := (_hash3(hash_x, top, hash_z, 71) % 3) - 1
	var lean_z := (_hash3(hash_x, top, hash_z, 72) % 3) - 1
	# Several deterministic crown profiles vary broadleaf silhouettes: compact
	# domes, fuller crowns, and narrower crowns with an uneven shoulder.
	var profile := _hash3(tree_world_x, top, tree_world_z, 73) % 4
	var layer_radii: Array
	if terrain_version == LEGACY_VERSION:
		layer_radii = [1, 2, 2, 3, 3, 2, 1] if radius >= 3 else [0, 1, 1, 2, 2, 1, 0]
	elif _is_m32() and radius >= 4:
		# M32 broadleaf crowns keep a wide middle and an uneven shoulder.  The
		# extra wide layer (and the per-layer shelf below) gives the stepped,
		# many-cornered silhouette of the reference instead of one smooth dome.
		match profile:
			0:
				layer_radii = [1, 2, 3, 4, 3, 3, 2, 2, 1]
			1:
				layer_radii = [0, 1, 2, 3, 4, 3, 2, 2, 1]
			2:
				layer_radii = [1, 2, 3, 3, 4, 3, 2, 1, 1]
			_:
				layer_radii = [1, 2, 4, 3, 3, 2, 2, 2, 1]
	elif _is_m32() and radius >= 3:
		match profile:
			0:
				layer_radii = [1, 2, 3, 3, 3, 2, 1]
			1:
				layer_radii = [0, 1, 2, 3, 3, 2, 1]
			2:
				layer_radii = [1, 2, 3, 2, 3, 2, 1]
			_:
				layer_radii = [1, 1, 2, 3, 2, 1, 1]
	elif radius >= 4:
		match profile:
			0:
				layer_radii = [1, 2, 3, 3, 4, 3, 3, 2, 1]
			1:
				layer_radii = [0, 1, 2, 3, 4, 4, 3, 2, 1]
			2:
				layer_radii = [1, 2, 3, 4, 4, 4, 3, 2, 1]
			_:
				layer_radii = [1, 2, 4, 3, 4, 3, 4, 2, 1]
	elif radius >= 3:
		match profile:
			0:
				layer_radii = [1, 2, 2, 3, 3, 2, 1]
			1:
				layer_radii = [0, 1, 2, 3, 3, 2, 1]
			2:
				layer_radii = [1, 2, 3, 3, 3, 2, 1]
			_:
				layer_radii = [1, 2, 3, 2, 3, 2, 1]
	else:
		match profile:
			0:
				layer_radii = [0, 1, 1, 2, 2, 1, 0]
			1:
				layer_radii = [0, 1, 2, 2, 2, 1, 0]
			2:
				layer_radii = [0, 0, 1, 2, 2, 1, 0]
			_:
				layer_radii = [0, 1, 1, 2, 1, 1, 0]
	for layer_index in layer_radii.size():
		var layer_radius: int = int(layer_radii[layer_index])
		var layer_centre := 4 if terrain_version != LEGACY_VERSION and radius >= 4 else 3
		if _is_m32():
			# Drop the crown one layer down the trunk.  The canopy then starts
			# closer to the ground and the bare-pole silhouette disappears.
			layer_centre = 5 if radius >= 4 else 4
		var dy := layer_index - layer_centre
		# Version 2 shifts each wide layer by up to one block, so the crown steps
		# out in shelves rather than stacking into a single smooth dome.
		var shelf_x := 0
		var shelf_z := 0
		if _is_wilderness() and layer_radius >= 2:
			shelf_x = (_hash3(tree_world_x, top + dy, tree_world_z, 81) % 3) - 1
			shelf_z = (_hash3(tree_world_x, top + dy, tree_world_z, 82) % 3) - 1
		for dz in range(-layer_radius, layer_radius + 1):
			for dx in range(-layer_radius, layer_radius + 1):
				if dx * dx + dz * dz > layer_radius * layer_radius + 1:
					continue
				if absi(dx) == layer_radius or absi(dz) == layer_radius:
					# Trim the outer ring irregularly (and the far corners more).
					# M32 trims a little harder so crowns read as rounded cubic
					# masses rather than square shelves.
					if absi(dx) == layer_radius and absi(dz) == layer_radius:
						if _hash3(hash_x + dx, top + dy, hash_z + dz, 5) % (2 if _is_m32() else 3) != 0:
							continue
					elif _hash3(hash_x + dx, top + dy, hash_z + dz, 6) % (4 if _is_m32() else 5) == 0:
						continue
				_place_block(chunk, local_x + dx + lean_x + shelf_x, top + dy, local_z + dz + lean_z + shelf_z, leaf_block, base_y, true)
	# A short, broken skirt around the trunk softens the flat underside of the
	# crown, which otherwise reads as a green slab floating over the trunk.  M32
	# continues the skirt two layers lower so the trunk-to-canopy transition is
	# leafy rather than a bare pole with a ball on top.
	if radius >= 3:
		var skirt_layers: Array = [top - 4]
		if _is_m32():
			skirt_layers = [top - 4, top - 3, top - 2]
		for skirt_index in skirt_layers.size():
			var skirt_y: int = int(skirt_layers[skirt_index])
			var salt := 23 + skirt_index
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if dx * dx + dz * dz > 5:
						continue
					if _hash3(hash_x + dx, skirt_y, hash_z + dz, salt) % (4 if _is_m32() else 3) == 0:
						_place_block(chunk, local_x + dx + lean_x, skirt_y, local_z + dz + lean_z,
							leaf_block, base_y, true)
	# A short branch on each side of the upper trunk gives the silhouette a
	# recognizable broadleaf shape instead of a single green blob.
	if trunk >= 6:
		_place_block(chunk, local_x + 1, top - 2, local_z, log_block, base_y, false)
		_place_block(chunk, local_x - 1, top - 1, local_z, log_block, base_y, false)
	_place_block(chunk, local_x, top + 2, local_z, leaf_block, base_y, true)


func _place_pine(chunk: ChunkData, local_x: int, base: int, local_z: int, trunk: int, base_y: int) -> void:
	for offset in trunk:
		_place_block(chunk, local_x, base + offset, local_z, BlockDB.PINE_LOG, base_y, false)
	var top := base + trunk
	var tree_world_x := chunk.coord.x * ChunkData.SIZE + local_x
	var tree_world_z := chunk.coord.z * ChunkData.SIZE + local_z
	# Conical tiers: wide near the base, narrowing to a point, with every other
	# layer one block smaller so the silhouette reads as a pine rather than a
	# cylinder.  The offsets give the tiers a slightly ragged edge.
	var hash_x := local_x if terrain_version == LEGACY_VERSION else tree_world_x
	var hash_z := local_z if terrain_version == LEGACY_VERSION else tree_world_z
	var profile := _hash3(tree_world_x, top, tree_world_z, 911) % 3
	var tier_radii: Array
	if terrain_version == LEGACY_VERSION:
		tier_radii = [1, 1, 2, 2, 3, 3, 2, 1]
	elif _is_m32():
		match profile:
			0:
				tier_radii = [1, 2, 2, 3, 3, 3, 2, 2, 1]
			1:
				tier_radii = [1, 2, 3, 3, 3, 2, 2, 1, 1]
			_:
				tier_radii = [1, 1, 2, 3, 3, 2, 2, 1, 1]
	else:
		match profile:
			0:
				tier_radii = [1, 1, 2, 2, 3, 3, 2, 1]
			1:
				tier_radii = [1, 2, 2, 3, 3, 2, 1, 1]
			_:
				tier_radii = [1, 1, 2, 3, 2, 2, 1, 1]
	for tier in tier_radii.size():
		var layer_radius: int = int(tier_radii[tier])
		var dy := tier - (8 if _is_m32() else 7)
		var lean := 1 if _hash3(hash_x, top + dy, hash_z, 909) % 5 == 0 else 0
		for dz in range(-layer_radius, layer_radius + 1):
			for dx in range(-layer_radius, layer_radius + 1):
				if layer_radius > 1 and absi(dx) + absi(dz) > layer_radius + 1:
					continue
				if absi(dx) == layer_radius and absi(dz) == layer_radius \
						and _hash3(hash_x + dx, top + dy, hash_z + dz, 17) % 3 != 0:
					continue
				_place_block(chunk, local_x + dx + lean, top + dy, local_z + dz,
					BlockDB.PINE_LEAVES, base_y, true)
	_place_block(chunk, local_x, top + 1, local_z, BlockDB.PINE_LEAVES, base_y, true)
	_place_block(chunk, local_x, top + 2, local_z, BlockDB.PINE_LEAVES, base_y, true)


## Sparse fallen trunks add a readable forest-floor landmark without changing
## the block vocabulary or introducing any remembered procedural state.
func _generate_fallen_logs(chunk: ChunkData) -> void:
	var coord := chunk.coord
	var base_x := coord.x * ChunkData.SIZE
	var base_y := coord.y * ChunkData.SIZE
	var base_z := coord.z * ChunkData.SIZE
	for local_z in range(-4, ChunkData.SIZE + 4):
		for local_x in range(-4, ChunkData.SIZE + 4):
			var world_x := base_x + local_x
			var world_z := base_z + local_z
			if _hash2(world_x, world_z, 9251) % 1000 >= 4:
				continue
			var height := _world_height(world_x, world_z)
			if height <= SEA_LEVEL or _world_biome(world_x, world_z) != Biome.FOREST:
				continue
			if _column_slope(world_x, world_z, height) > 1:
				continue
			var length := 2 + _hash2(world_x, world_z, 9252) % 3
			var along_x := _hash2(world_x, world_z, 9253) % 2 == 0
			var sign := -1 if _hash2(world_x, world_z, 9254) % 2 == 0 else 1
			var log_id := BlockDB.BIRCH_LOG if _hash2(world_x, world_z, 9255) % 4 == 0 else BlockDB.OAK_LOG
			if _hash2(world_x, world_z, 9255) % 4 == 1:
				log_id = BlockDB.PINE_LOG
			for step in length:
				var segment_x := world_x + (step * sign if along_x else 0)
				var segment_z := world_z + (step * sign if not along_x else 0)
				var segment_height := _world_height(segment_x, segment_z)
				if absi(segment_height - height) > 1 or int(tree_at(segment_x, segment_z)["type"]) != TreeType.NONE:
					break
				_place_block(chunk, segment_x - base_x, segment_height + 1,
					segment_z - base_z, log_id, base_y, true)


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
