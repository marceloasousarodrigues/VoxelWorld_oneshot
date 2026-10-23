class_name BlockPlacementPreview
extends Node3D

## World-space ghost of the block that the current placement action would create.
##
## The ghost geometry is built by the real `ChunkMesher`, not by a second model:
## a one-cell isolated chunk is meshed with the exact block id and orientation
## that `VoxelPlayer.placement_preview()` returns.  A preview therefore cannot
## disagree with the shape the world will render after placement (cube, slab,
## stair, ramp, ridge, station, ...).  The target surface and the destination
## cell are drawn separately: an amber face patch marks the aimed surface, the
## ghost and its outline mark the destination cell, a 3D arrow and a cyan
## forward-face/axis marker show the facing of directional pieces.

const BlockShape = preload("res://scripts/core/block_shape.gd")

const VALID_COLOR := Color(0.22, 0.95, 0.45, 0.34)
const INVALID_COLOR := Color(1.0, 0.20, 0.16, 0.46)
const OUTLINE_VALID := Color(0.10, 1.0, 0.35, 0.95)
const OUTLINE_INVALID := Color(1.0, 0.17, 0.12, 0.98)
const SURFACE_COLOR := Color(1.0, 0.80, 0.22, 0.34)
const DIRECTION_COLOR := Color(0.10, 0.82, 1.0, 0.55)
const ARROW_COLOR := Color(1.0, 0.86, 0.18, 0.98)

var _preview_mesher: ChunkMesher
var _preview_world: VoxelWorld
var _preview_chunk: ChunkData
var _ghost: MeshInstance3D
var _outline: MeshInstance3D
var _surface: MeshInstance3D
var _direction_face: MeshInstance3D
var _arrow: Node3D
var _ghost_material: StandardMaterial3D
var _outline_material: StandardMaterial3D
var _surface_material: StandardMaterial3D
var _direction_material: StandardMaterial3D
var _arrow_material: StandardMaterial3D

var _showing := false
var _valid := true
var _cell := Vector3i.ZERO
var _block_id := BlockDB.AIR
var _orientation := 0
var _target_cell := Vector3i.ZERO
var _target_normal := Vector3i.ZERO
var _mesh_key := ""


func setup(chunk_mesher: ChunkMesher) -> void:
	if chunk_mesher == null or _ghost != null:
		return
	# A private mesher keeps preview rebuilds out of the streaming mesher's
	# counters, which are part of the performance evidence.
	_preview_mesher = ChunkMesher.new(chunk_mesher.library, chunk_mesher.materials)
	_preview_world = VoxelWorld.new(17017)
	_preview_chunk = ChunkData.new(Vector3i.ZERO)
	_preview_chunk.generated = true
	_preview_world.adopt_chunk(_preview_chunk)

	_ghost_material = _make_material(VALID_COLOR)
	_outline_material = _make_material(OUTLINE_VALID)
	_surface_material = _make_material(SURFACE_COLOR)
	_direction_material = _make_material(DIRECTION_COLOR)
	_arrow_material = _make_material(ARROW_COLOR)

	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_ghost.material_override = _ghost_material
	add_child(_ghost)

	_outline = MeshInstance3D.new()
	_outline.name = "CellOutline"
	_outline.mesh = _build_outline_mesh()
	_outline.material_override = _outline_material
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_outline)

	_surface = MeshInstance3D.new()
	_surface.name = "TargetSurface"
	_surface.material_override = _surface_material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_surface)

	_direction_face = MeshInstance3D.new()
	_direction_face.name = "FacingFace"
	_direction_face.material_override = _direction_material
	_direction_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_direction_face.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_direction_face)

	_arrow = Node3D.new()
	_arrow.name = "FacingArrow"
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.075, 0.075, 0.45)
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, 0.0, 0.27)
	shaft.material_override = _arrow_material
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_arrow.add_child(shaft)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.135
	head_mesh.height = 0.28
	head_mesh.radial_segments = 8
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.0, 0.62)
	head.rotation.x = PI * 0.5
	head.material_override = _arrow_material
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_arrow.add_child(head)
	_arrow.position = Vector3(0.5, 1.15, 0.5)
	add_child(_arrow)
	visible = false


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.render_priority = 2
	return material


## Shows the ghost at the preview's destination.  `preview` is the dictionary
## returned by `VoxelPlayer.placement_preview()`.  An empty preview, a missing
## cell, or `show == false` (no target / outside the loaded build range) hides
## the ghost instead of drawing a misleading marker.
func update_preview(preview: Dictionary) -> void:
	if _ghost == null:
		return
	if preview.is_empty() or not bool(preview.get("show", true)) \
			or not preview.has("cell"):
		hide_preview()
		return
	_cell = preview["cell"]
	_block_id = int(preview["block"])
	_orientation = int(preview.get("orientation", 0))
	_target_cell = preview.get("target", _cell)
	_target_normal = preview.get("normal", Vector3i.ZERO)
	_valid = bool(preview.get("valid", false))
	var cell_key := "%d,%d,%d|%d|%d|%d,%d,%d|%d,%d,%d" % [
		_cell.x, _cell.y, _cell.z, _block_id, _orientation,
		_target_cell.x, _target_cell.y, _target_cell.z,
		_target_normal.x, _target_normal.y, _target_normal.z,
	]
	if cell_key != _mesh_key:
		_mesh_key = cell_key
		_rebuild_ghost_mesh()
		position = Vector3(_cell)
		_rebuild_surface()
		_update_arrow()
	_set_state(_valid)
	visible = true
	_showing = true


func hide_preview() -> void:
	_showing = false
	visible = false
	_mesh_key = ""


func is_showing() -> bool:
	return _showing


func is_valid() -> bool:
	return _valid


func preview_cell() -> Vector3i:
	return _cell


func preview_block() -> int:
	return _block_id


func preview_orientation() -> int:
	return _orientation


func preview_mesh() -> Mesh:
	return _ghost.mesh if _ghost != null else null


func _rebuild_ghost_mesh() -> void:
	_preview_chunk.blocks.fill(BlockDB.AIR)
	_preview_chunk.orientations.fill(0)
	var index := ChunkData.cell_index(0, 0, 0)
	_preview_chunk.blocks[index] = _block_id
	_preview_chunk.orientations[index] = _orientation
	var geometry: Dictionary = _preview_mesher.build_geometry(
		_preview_mesher.capture_input(_preview_chunk, _preview_world))
	var mesh := ArrayMesh.new()
	for surface: Dictionary in geometry["surfaces"]:
		var indices: PackedInt32Array = surface["index"]
		if indices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface["vertex"]
		arrays[Mesh.ARRAY_NORMAL] = surface["normal"]
		arrays[Mesh.ARRAY_TEX_UV] = surface["uv"]
		arrays[Mesh.ARRAY_TEX_UV2] = surface["uv2"]
		arrays[Mesh.ARRAY_COLOR] = surface["color"]
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ghost.mesh = mesh


func _set_state(valid: bool) -> void:
	_valid = valid
	_ghost_material.albedo_color = VALID_COLOR if valid else INVALID_COLOR
	_outline_material.albedo_color = OUTLINE_VALID if valid else OUTLINE_INVALID
	# An invalid destination is often occupied by a real block.  Drawing the red
	# ghost through it (and above transparent neighbours) makes the refusal
	# unmistakable instead of leaving only a thin outline behind an opaque cube.
	_ghost_material.no_depth_test = not valid
	_outline_material.no_depth_test = not valid
	_ghost_material.render_priority = 4 if not valid else 2
	_outline_material.render_priority = 4 if not valid else 2


## A translucent patch on the face the crosshair actually hit.  It sits a few
## millimetres proud of the surface so it cannot z-fight with the chunk mesh.
func _rebuild_surface() -> void:
	var mesh := ImmediateMesh.new()
	if _target_normal == Vector3i.ZERO:
		_surface.mesh = mesh
		return
	var centre := Vector3(_target_cell) + Vector3(0.5, 0.5, 0.5) \
		+ Vector3(_target_normal) * 0.505
	var first := Vector3.RIGHT
	var second := Vector3.UP
	if absi(_target_normal.x) == 1:
		first = Vector3.UP
		second = Vector3.BACK
	elif absi(_target_normal.y) == 1:
		first = Vector3.RIGHT
		second = Vector3.BACK
	var half := 0.46
	var corners: Array[Vector3] = [
		centre - first * half - second * half,
		centre + first * half - second * half,
		centre + first * half + second * half,
		centre - first * half + second * half,
	]
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _surface_material)
	for corner_index in [0, 1, 2, 0, 2, 3]:
		mesh.surface_add_vertex(corners[corner_index])
	mesh.surface_end()
	_surface.mesh = mesh


func _update_arrow() -> void:
	var directional := _block_id == BlockDB.STAIR or _block_id == BlockDB.SLATE_STAIR \
		or _block_id == BlockDB.SLATE_RIDGE or _block_id == BlockDB.SLATE_RAMP
	_arrow.visible = directional
	_direction_face.visible = directional
	if not directional:
		_direction_face.mesh = null
		return
	var direction := _facing_direction(_block_id, _orientation)
	if direction == Vector3.ZERO:
		_arrow.visible = false
		_direction_face.visible = false
		return
	_arrow.rotation.y = atan2(direction.x, direction.z)
	if _block_id == BlockDB.SLATE_RIDGE:
		# A ridge has an axis, not a front: draw a bright strip along its length.
		_direction_face.mesh = _build_axis_strip(direction)
	else:
		# Stairs and ramps get a highlighted forward face in addition to the 3D
		# arrow, so the chosen rotation reads from above and from the side.
		_direction_face.mesh = _build_forward_face(direction)


## A highlight on the vertical cell face the shaped piece faces.  Cyan is used
## deliberately: green/red already mean valid/invalid, amber marks the targeted
## surface, so rotation feedback needs its own colour.
func _build_forward_face(direction: Vector3) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var centre := Vector3(0.5, 0.5, 0.5) + direction * 0.505
	var first := Vector3.RIGHT
	if absf(direction.x) > 0.5:
		first = Vector3.BACK
	var second := Vector3.UP
	var half := 0.40
	var corners: Array[Vector3] = [
		centre - first * half - second * half,
		centre + first * half - second * half,
		centre + first * half + second * half,
		centre - first * half + second * half,
	]
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _direction_material)
	for corner_index in [0, 1, 2, 0, 2, 3]:
		mesh.surface_add_vertex(corners[corner_index])
	mesh.surface_end()
	return mesh


func _build_axis_strip(direction: Vector3) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var centre := Vector3(0.5, 1.035, 0.5)
	var across := Vector3(direction.z, 0.0, direction.x)
	var half_length := 0.46
	var half_width := 0.09
	var corners: Array[Vector3] = [
		centre - direction * half_length - across * half_width,
		centre + direction * half_length - across * half_width,
		centre + direction * half_length + across * half_width,
		centre - direction * half_length + across * half_width,
	]
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _direction_material)
	for corner_index in [0, 1, 2, 0, 2, 3]:
		mesh.surface_add_vertex(corners[corner_index])
	mesh.surface_end()
	return mesh


## The direction the player deliberately chose for a shaped piece.  Stairs and
## ramps use the existing +Z/+X/-Z/-X facing convention (the canonical model
## descends toward +Z); a ridge uses its long axis (X for even orientations,
## Z for odd ones).  Slabs have no horizontal facing, so they rely on their
## visible half and the HUD state label instead of an arrow.
func _facing_direction(block_id: int, orientation: int) -> Vector3:
	if block_id == BlockDB.SLATE_RIDGE:
		return Vector3.RIGHT if orientation % 2 == 0 else Vector3.BACK
	var facings: Array[Vector3] = [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
	return facings[orientation % 4]


func _build_outline_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var low := Vector3(-0.004, -0.004, -0.004)
	var high := Vector3(1.004, 1.004, 1.004)
	var corners: Array[Vector3] = [
		Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z),
		Vector3(high.x, low.y, high.z), Vector3(low.x, low.y, high.z),
		Vector3(low.x, high.y, low.z), Vector3(high.x, high.y, low.z),
		Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _outline_material)
	for edge: Array in edges:
		mesh.surface_add_vertex(corners[int(edge[0])])
		mesh.surface_add_vertex(corners[int(edge[1])])
	mesh.surface_end()
	return mesh



