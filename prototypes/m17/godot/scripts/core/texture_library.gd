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
				images.append(_prepare(slot))
		else:
			images.append(_prepare(image))
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


func _prepare(image: Image) -> Image:
	if image.get_width() != TILE_SIZE or image.get_height() != TILE_SIZE:
		var interpolation := Image.INTERPOLATE_LANCZOS if image.get_width() > TILE_SIZE else Image.INTERPOLATE_NEAREST
		image.resize(TILE_SIZE, TILE_SIZE, interpolation)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	return image


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
