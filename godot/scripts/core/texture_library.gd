class_name TextureLibrary
extends RefCounted

## Loads the vendored block textures and packs them into a Godot
## `Texture2DArray`.
##
## A texture array is used instead of a classic atlas so mipmapping never bleeds
## neighbouring tiles into each other: every tile keeps its own layer.  The mesh
## carries the layer index in `ARRAY_TEX_UV2.x` and the shaders sample
## `texture(atlas, vec3(UV, layer))`.
##
## Animated strips (water) contribute one layer per frame, so a shader can pick
## `base_layer + time_step`.

const TILE_SIZE := 128
const SOURCES_PATH := "res://assets/texture_sources.json"

## M18 material grading.  The vendored Minetest textures are high-saturation
## pixel art; at one tile per metre, their neon greens and noisy contrast read as
## raw assets rather than a designed palette.  These per-texture
## brightness/contrast/saturation values pull them toward the M18 palette
## (restrained grass, umber soil, cool stone, warm sand) while keeping the
## source art and its attribution untouched on disk.
const GRADE := {
	"grass_top": [0.82, 1.04, 0.28],
	"grass_side": [0.86, 1.02, 0.35],
	"dry_grass_top": [0.93, 1.01, 0.58],
	"dry_grass_side": [0.93, 1.01, 0.66],
	"oak_leaves": [0.90, 1.01, 0.46],
	"pine_leaves": [0.88, 1.01, 0.44],
	"dirt": [0.92, 1.02, 0.76],
	"stone": [0.88, 1.03, 0.88],
	"cobble": [0.80, 1.04, 0.86],
	"gravel": [0.90, 1.03, 0.84],
	"sand": [0.95, 1.01, 0.80],
	"sandstone": [0.95, 1.01, 0.80],
	"brick": [0.86, 1.02, 0.60],
	"stone_brick": [0.62, 1.06, 0.86],
	"mossy_cobble": [0.82, 1.03, 0.74],
	"planks": [0.95, 1.01, 0.86],
	"oak_log_side": [0.94, 1.01, 0.86],
	"oak_log_top": [0.94, 1.01, 0.86],
	"pine_log_side": [0.94, 1.01, 0.86],
	"pine_log_top": [0.94, 1.01, 0.86],
	"furnace_side": [0.92, 1.01, 0.84],
	"furnace_top": [0.94, 1.01, 0.86],
	"water_anim": [0.94, 1.01, 0.55],
	"deco_grass_1": [0.92, 1.02, 0.58],
	"deco_grass_2": [0.92, 1.02, 0.58],
	"deco_grass_3": [0.92, 1.02, 0.58],
	"deco_grass_4": [0.92, 1.02, 0.58],
	"deco_grass_5": [0.92, 1.02, 0.58],
	"deco_jungle_grass": [0.92, 1.02, 0.56],
	"deco_dry_grass": [0.95, 1.0, 0.72],
	"cactus_side": [0.94, 1.01, 0.66],
	"cactus_top": [0.94, 1.01, 0.66],
	# M29 medieval palette: the procedural art is already drawn for the world
	# palette, so these grades only pull the new materials a little closer to the
	# existing grass/stone/plank tones instead of restyling them.
	"plaster": [1.0, 1.0, 0.94],
	"dark_timber": [0.96, 1.02, 0.88],
	"stone_wall": [0.96, 1.0, 0.92],
	"timber_brace": [0.98, 1.0, 0.92],
	"slate_tile": [1.0, 1.02, 0.72],
	"slate_ridge": [1.0, 1.02, 0.72],
	"slate_side": [1.0, 1.02, 0.72],
	"window": [0.98, 1.0, 0.90],
	"shutter": [0.96, 1.0, 0.9],
	"chimney_side": [0.94, 1.0, 0.9],
	"chimney_top": [0.94, 1.0, 0.9],
	"finial": [1.0, 1.0, 0.94],
	"flower_box": [1.0, 1.0, 0.94],
	"flower_box_bloom": [0.98, 1.02, 0.92],
}

## Small channel multipliers applied after `adjust_bcs` to warm soil and foliage
## and cool stone, keeping one consistent light direction across materials.
const GRADE_TINT := {
	"grass_top": [1.10, 1.0, 0.88],
	"grass_side": [1.05, 1.0, 0.94],
	"oak_leaves": [1.02, 1.0, 0.92],
	"pine_leaves": [0.98, 1.0, 0.95],
	"dirt": [1.05, 1.0, 0.93],
	"stone": [1.0, 1.0, 1.0],
	"cobble": [1.0, 0.995, 1.0],
	"stone_brick": [1.0, 0.99, 0.97],
	"sand": [1.05, 1.0, 0.92],
	"sandstone": [1.05, 1.0, 0.92],
	"brick": [1.0, 0.96, 0.94],
	"planks": [1.03, 1.0, 0.95],
	"oak_log_side": [1.03, 1.0, 0.95],
	"oak_log_top": [1.03, 1.0, 0.95],
	"deco_grass_1": [1.0, 1.0, 0.95],
	"deco_grass_2": [1.0, 1.0, 0.95],
	"deco_grass_3": [1.0, 1.0, 0.95],
	"deco_grass_4": [1.0, 1.0, 0.95],
	"deco_grass_5": [1.0, 1.0, 0.95],
}

var tiles: PackedStringArray = PackedStringArray()
var layer_of: Dictionary = {}
var animated: Dictionary = {}
var icon_cache: Dictionary = {}
## The prepared source images, kept alongside the array so HUD icons can be built
## without asking the renderer for layer data (which is unavailable headless).
var layer_images: Array[Image] = []
var array: Texture2DArray
var report: Dictionary = {}


func load_all() -> bool:
	var file := FileAccess.open(SOURCES_PATH, FileAccess.READ)
	if file == null:
		push_error("TextureLibrary: cannot open %s" % SOURCES_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TextureLibrary: %s is not valid JSON" % SOURCES_PATH)
		return false
	var sources: Dictionary = parsed["textures"]
	var images: Array[Image] = []
	var keys: Array = sources.keys()
	keys.sort()
	var missing: Array[String] = []
	for key: String in keys:
		var entry: Dictionary = sources[key]
		var path := "res://assets/textures/%s" % str(entry["file"])
		var image := _load_image(path)
		if image == null:
			missing.append(path)
			continue
		var frames := int(entry.get("frames", 1))
		if frames > 1:
			if image.get_height() != image.get_width() * frames:
				push_error("TextureLibrary: %s strip is not %d stacked frames" % [path, frames])
				continue
			animated[key] = {"base": images.size(), "frames": frames}
			for frame in frames:
				var slot := Image.create(image.get_width(), image.get_width(), false, image.get_format())
				slot.blit_rect(image, Rect2i(0, frame * image.get_width(), image.get_width(), image.get_width()), Vector2i.ZERO)
				images.append(_prepare(slot, key))
		else:
			images.append(_prepare(image, key))
		layer_of[key] = images.size() - 1 if frames <= 1 else images.size() - frames
		tiles.append(key)
	if not missing.is_empty():
		push_error("TextureLibrary: missing %d texture files: %s" % [missing.size(), ", ".join(missing)])
		return false
	if images.is_empty():
		push_error("TextureLibrary: no textures loaded")
		return false
	layer_images = images
	array = Texture2DArray.new()
	var error := array.create_from_images(images)
	if error != OK:
		push_error("TextureLibrary: Texture2DArray.create_from_images failed (%d)" % error)
		return false
	report = {
		"tiles": tiles.size(),
		"layers": images.size(),
		"size": TILE_SIZE,
		"animated": animated.size(),
	}
	return true


func _load_image(path: String) -> Image:
	# Dev-project loading: read the PNG straight from the project directory so no
	# import step is required. Falls back to the resource loader.
	var absolute := ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(absolute) == OK:
		return image
	var resource := ResourceLoader.load(path)
	if resource is Texture2D:
		return (resource as Texture2D).get_image()
	push_error("TextureLibrary: could not load %s" % path)
	return null


func _prepare(image: Image, key: String) -> Image:
	if image.get_width() != TILE_SIZE or image.get_height() != TILE_SIZE:
		var interpolation := Image.INTERPOLATE_LANCZOS if image.get_width() > TILE_SIZE else Image.INTERPOLATE_NEAREST
		image.resize(TILE_SIZE, TILE_SIZE, interpolation)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_grade(image, key)
	image.generate_mipmaps()
	return image


func _grade(image: Image, key: String) -> void:
	var factors: Variant = GRADE.get(key)
	if factors != null:
		image.adjust_bcs(float(factors[0]), float(factors[1]), float(factors[2]))
	var tint: Variant = GRADE_TINT.get(key)
	if tint == null:
		return
	var red := float(tint[0])
	var green := float(tint[1])
	var blue := float(tint[2])
	var data := image.get_data()
	for index in range(0, data.size(), 4):
		data[index] = clampi(int(float(data[index]) * red), 0, 255)
		data[index + 1] = clampi(int(float(data[index + 1]) * green), 0, 255)
		data[index + 2] = clampi(int(float(data[index + 2]) * blue), 0, 255)
	image.set_data(image.get_width(), image.get_height(), false, image.get_format(), data)


func layer_index(key: String) -> int:
	return int(layer_of.get(key, 0))


func animated_base(key: String) -> int:
	var entry: Variant = animated.get(key)
	if entry == null:
		return -1
	return int((entry as Dictionary)["base"])


func animated_frames(key: String) -> int:
	var entry: Variant = animated.get(key)
	if entry == null:
		return 0
	return int((entry as Dictionary)["frames"])


## Small Texture2D for HUD icons (hotbar slots).
func icon(key: String) -> Texture2D:
	if icon_cache.has(key):
		return icon_cache[key]
	var index := layer_index(key)
	if index < 0 or index >= layer_images.size():
		return null
	var image: Image = layer_images[index].duplicate()
	image.clear_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	icon_cache[key] = texture
	return texture
