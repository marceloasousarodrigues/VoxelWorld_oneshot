class_name VoxelMaterials
extends RefCounted

## Builds and owns the five voxel render-layer materials that share one texture
## array.  Textures and shaders are loaded once and reused by every chunk mesh.

const SHADERS := {
	BlockDB.LAYER_OPAQUE: "res://shaders/voxel_opaque.gdshader",
	BlockDB.LAYER_CUTOUT: "res://shaders/voxel_cutout.gdshader",
	BlockDB.LAYER_BLEND: "res://shaders/voxel_blend.gdshader",
	BlockDB.LAYER_WATER: "res://shaders/voxel_water.gdshader",
	BlockDB.LAYER_DECO: "res://shaders/voxel_deco.gdshader",
}

var library: TextureLibrary
var materials: Dictionary = {}
var water_frame_rate := 3.0


func _init(texture_library: TextureLibrary) -> void:
	library = texture_library
	build()


func build() -> void:
	for layer: int in SHADERS:
		var path: String = SHADERS[layer]
		if not ResourceLoader.exists(path):
			push_error("VoxelMaterials: missing shader %s" % path)
			continue
		var shader: Shader = load(path)
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("atlas", library.array)
		if layer == BlockDB.LAYER_WATER:
			var frames := library.animated_frames("water_anim")
			material.set_shader_parameter("frames", float(frames if frames > 0 else 1))
			material.set_shader_parameter("frame_rate", water_frame_rate)
			material.render_priority = 1
		materials[layer] = material


func for_layer(layer: int) -> Material:
	return materials.get(layer, null)


func water_material() -> ShaderMaterial:
	return materials.get(BlockDB.LAYER_WATER, null)
