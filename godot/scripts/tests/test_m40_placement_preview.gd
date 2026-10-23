extends RefCounted

## M40 placement preview contract.
##
## The ghost is not compared against a separate mock model: every geometry check
## reads the mesh that `BlockPlacementPreview` built from the real `ChunkMesher`.
## The same `placement_preview()` dictionary drives the HUD, the ghost and the
## actual `place_selected()` transaction, so cell/orientation equality here is a
## direct proof that the preview cannot disagree with placement.

const Preview = preload("res://scripts/game/block_placement_preview.gd")

var _library: TextureLibrary
var _materials: VoxelMaterials
var _mesher: ChunkMesher


func name() -> String:
	return "M40 placement preview"


func run(h: TestHarness) -> void:
	_setup()
	_test_cube_placement(h)
	_test_slab_placement(h)
	_test_directional_rotation(h)
	_test_invalid_and_item_changes(h)
	_finish_scene()
	h.finish()


func _setup() -> void:
	_library = TextureLibrary.new()
	_library.load_all()
	_materials = VoxelMaterials.new(_library)
	_mesher = ChunkMesher.new(_library, _materials)


func _world() -> VoxelWorld:
	var world := VoxelWorld.new(17017)
	var chunk := ChunkData.new(Vector3i.ZERO)
	chunk.generated = true
	world.adopt_chunk(chunk)
	return world


func _player(world: VoxelWorld) -> VoxelPlayer:
	var player := VoxelPlayer.new()
	player.world = world
	player.inventory = Inventory.new()
	player.set_process(false)
	player.set_physics_process(false)
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.teleport_to(Vector3(100.0, 100.0, 100.0))
	player.look_yaw(0.0)
	return player


func _ghost():
	var ghost = Preview.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(ghost)
	ghost.setup(_mesher)
	return ghost


func _hit(cell: Vector3i, normal: Vector3i, block_id: int = BlockDB.STONE) -> Dictionary:
	return {"hit": true, "block": cell, "normal": normal, "block_id": block_id}


func _select(player: VoxelPlayer, item_id: int) -> void:
	player.inventory.clear_slot(0)
	player.inventory.put_stack(0, {"item": item_id, "count": 32})
	player.inventory.select(0)


func _mesh_signature(mesh: Mesh) -> String:
	if mesh == null or mesh.get_surface_count() == 0:
		return ""
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var parts: Array[String] = []
	for vertex: Vector3 in vertices:
		parts.append("%.3f,%.3f,%.3f" % [vertex.x, vertex.y, vertex.z])
	return "|".join(parts)


func _test_cube_placement(h: TestHarness) -> void:
	h.section("M40 preview: cube on top and against every side")
	var world := _world()
	var player := _player(world)
	var ghost = _ghost()
	_select(player, BlockDB.STONE)

	# Top face: the destination is the cell above the target.
	var top_target := Vector3i(8, 8, 8)
	world.set_block(top_target, BlockDB.STONE)
	player._hit = _hit(top_target, Vector3i.UP)
	var preview: Dictionary = player.placement_preview()
	h.check(bool(preview["valid"]), "a cube preview on a top face is valid")
	h.eq(preview["cell"], Vector3i(8, 9, 8), "the top-face preview targets the cell above")
	h.eq(preview["orientation"], 0, "a full cube has no orientation")
	h.check(bool(preview["show"]), "the valid top-face preview is visible")
	ghost.update_preview(preview)
	h.check(ghost.is_showing(), "the ghost is shown for a top-face cube")
	h.eq(ghost.preview_cell(), preview["cell"], "the ghost cell equals the preview cell")
	h.eq(ghost.position, Vector3(8, 9, 8), "the ghost is positioned at the exact destination cell")
	h.eq(ghost.preview_block(), BlockDB.STONE, "the ghost uses the selected block")
	var bounds: AABB = ghost.preview_mesh().get_aabb()
	h.approx(bounds.size.x, 1.0, 0.01, "the cube ghost is one cell wide")
	h.approx(bounds.size.y, 1.0, 0.01, "the cube ghost is one cell high")
	h.approx(bounds.size.z, 1.0, 0.01, "the cube ghost is one cell deep")
	var shown_cell: Vector3i = preview["cell"]
	var shown_orientation := int(preview["orientation"])
	h.check(player.place_selected(), "the cube can be placed from the preview")
	h.eq(world.get_block(shown_cell), BlockDB.STONE, "the placed cube is in the previewed cell")
	h.eq(world.get_orientation(shown_cell), shown_orientation,
		"the placed cube has the previewed orientation")

	# Side faces: four separate destinations around one target block.
	var side_target := Vector3i(10, 8, 8)
	world.set_block(side_target, BlockDB.STONE)
	for normal: Vector3i in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.BACK, Vector3i.FORWARD]:
		var cell := side_target + normal
		world.set_block(cell, BlockDB.AIR)
		player._hit = _hit(side_target, normal)
		var side_preview: Dictionary = player.placement_preview()
		h.check(bool(side_preview["valid"]),
			"a cube preview against side %s is valid" % str(normal))
		h.eq(side_preview["cell"], cell,
			"the side-face preview targets the adjacent cell for %s" % str(normal))
		ghost.update_preview(side_preview)
		h.eq(ghost.preview_cell(), side_preview["cell"],
			"the ghost matches the side-face destination for %s" % str(normal))
		var side_cell: Vector3i = side_preview["cell"]
		h.check(player.place_selected(), "the side-face cube can be placed for %s" % str(normal))
		h.eq(world.get_block(side_cell), BlockDB.STONE,
			"the side-face cube landed in the previewed cell for %s" % str(normal))

	player.queue_free()
	ghost.queue_free()


func _test_slab_placement(h: TestHarness) -> void:
	h.section("M40 preview: slab lower and upper half")
	var world := _world()
	var player := _player(world)
	var ghost = _ghost()
	_select(player, BlockDB.SLATE_SLAB)

	var top_target := Vector3i(8, 8, 8)
	world.set_block(top_target, BlockDB.STONE)
	player._hit = _hit(top_target, Vector3i.UP)
	var bottom: Dictionary = player.placement_preview()
	h.check(bool(bottom["valid"]), "a slab preview on a top face is valid")
	h.check(int(bottom["orientation"]) < 4, "a top-face hit previews the lower slab state")
	h.eq(VoxelPlayer.orientation_label(BlockDB.SLATE_SLAB, int(bottom["orientation"])),
		"bottom half", "the bottom slab state has a precise label")
	ghost.update_preview(bottom)
	var lower: AABB = ghost.preview_mesh().get_aabb()
	h.approx(lower.position.y, 0.0, 0.01, "the lower slab ghost starts at the cell floor")
	h.approx(lower.size.y, 0.5, 0.01, "the lower slab ghost fills exactly half the cell")
	h.approx(lower.size.x, 1.0, 0.01, "the lower slab ghost uses the real slab width")
	h.approx(lower.size.z, 1.0, 0.01, "the lower slab ghost uses the real slab depth")
	var lower_cell: Vector3i = bottom["cell"]
	h.check(player.place_selected(), "the lower slab can be placed from the preview")
	h.eq(world.get_orientation(lower_cell), int(bottom["orientation"]),
		"the placed lower slab has the previewed orientation")

	var ceiling_target := Vector3i(10, 8, 8)
	world.set_block(ceiling_target, BlockDB.STONE)
	world.set_block(ceiling_target + Vector3i.DOWN, BlockDB.AIR)
	player._hit = _hit(ceiling_target, Vector3i.DOWN)
	var top: Dictionary = player.placement_preview()
	h.check(bool(top["valid"]), "a slab preview on an underside is valid")
	h.check(int(top["orientation"]) >= 4, "an underside hit previews the upper slab state")
	h.eq(VoxelPlayer.orientation_label(BlockDB.SLATE_SLAB, int(top["orientation"])),
		"top half (upside down)", "the upper slab state has a precise label")
	ghost.update_preview(top)
	var upper: AABB = ghost.preview_mesh().get_aabb()
	h.approx(upper.position.y, 0.5, 0.01, "the upper slab ghost starts at the cell midpoint")
	h.approx(upper.size.y, 0.5, 0.01, "the upper slab ghost fills exactly half the cell")
	var upper_cell: Vector3i = top["cell"]
	h.check(player.place_selected(), "the upper slab can be placed from the preview")
	h.eq(world.get_orientation(upper_cell), int(top["orientation"]),
		"the placed upper slab has the previewed orientation")
	h.eq(ghost.preview_cell(), upper_cell, "the ghost still reports the upper slab destination")

	player.queue_free()
	ghost.queue_free()


func _test_directional_rotation(h: TestHarness) -> void:
	h.section("M40 preview: every stair / ramp / ridge orientation")
	var world := _world()
	var player := _player(world)
	var ghost = _ghost()
	_select(player, BlockDB.STAIR)
	var signatures := {}

	# Stairs support all eight orientations: four facings, each upright and
	# upside down.  A downward hit supplies the upside-down bit.
	for orientation in 8:
		var target := Vector3i(8, 8, 2 + orientation)
		world.set_block(target, BlockDB.STONE)
		var normal := Vector3i.UP if orientation < 4 else Vector3i.DOWN
		var destination := target + normal
		world.set_block(destination, BlockDB.AIR)
		player.placement_facing = orientation if orientation < 4 else orientation - 4
		player._hit = _hit(target, normal)
		var preview: Dictionary = player.placement_preview()
		h.check(bool(preview["valid"]), "stair orientation %d previews as valid" % orientation)
		h.eq(preview["orientation"], orientation,
			"stair orientation %d is derived from the facing and hit face" % orientation)
		ghost.update_preview(preview)
		h.eq(ghost.preview_orientation(), orientation,
			"the stair ghost shows orientation %d" % orientation)
		h.eq(ghost.preview_cell(), destination,
			"the stair ghost is in the exact destination cell for orientation %d" % orientation)
		signatures[orientation] = _mesh_signature(ghost.preview_mesh())
		var shown_cell: Vector3i = preview["cell"]
		h.check(player.place_selected(), "the stair can be placed at orientation %d" % orientation)
		h.eq(world.get_block(shown_cell), BlockDB.STAIR,
			"the placed stair is present at orientation %d" % orientation)
		h.eq(world.get_orientation(shown_cell), orientation,
			"placement preserves previewed stair orientation %d" % orientation)
	h.check(signatures[0] != signatures[1],
		"the stair ghost geometry actually changes between +Z and +X")
	h.check(signatures[0] != signatures[4],
		"the upside-down stair ghost is not the upright geometry")

	# Ramps use the same four horizontal facings and never flip upside down.
	_select(player, BlockDB.SLATE_RAMP)
	for orientation in 4:
		var target := Vector3i(4 + orientation * 2, 8, 8)
		world.set_block(target, BlockDB.STONE)
		world.set_block(target + Vector3i.UP, BlockDB.AIR)
		player.placement_facing = orientation
		player._hit = _hit(target, Vector3i.UP)
		var preview: Dictionary = player.placement_preview()
		h.eq(preview["orientation"], orientation,
			"ramp orientation %d is preserved" % orientation)
		ghost.update_preview(preview)
		var cell: Vector3i = preview["cell"]
		h.check(player.place_selected(), "the ramp can be placed at orientation %d" % orientation)
		h.eq(world.get_orientation(cell), orientation,
			"placement preserves ramp orientation %d" % orientation)

	# The ridge has two long-axis states; both must be visible and preserved.
	_select(player, BlockDB.SLATE_RIDGE)
	for axis in 2:
		var target := Vector3i(8, 8, 12 + axis)
		world.set_block(target, BlockDB.STONE)
		world.set_block(target + Vector3i.UP, BlockDB.AIR)
		player.placement_facing = axis
		player._hit = _hit(target, Vector3i.UP)
		var preview: Dictionary = player.placement_preview()
		h.eq(preview["orientation"], axis, "ridge axis %d is previewed" % axis)
		ghost.update_preview(preview)
		h.eq(ghost.preview_orientation(), axis, "the ridge ghost shows axis %d" % axis)
		var cell: Vector3i = preview["cell"]
		h.check(player.place_selected(), "the ridge can be placed on axis %d" % axis)
		h.eq(world.get_orientation(cell), axis, "placement preserves ridge axis %d" % axis)

	player.queue_free()
	ghost.queue_free()


func _test_invalid_and_item_changes(h: TestHarness) -> void:
	h.section("M40 preview: invalid cells, player collision and item changes")
	var world := _world()
	var player := _player(world)
	var ghost = _ghost()
	_select(player, BlockDB.STONE)

	var target := Vector3i(8, 8, 8)
	world.set_block(target, BlockDB.STONE)
	world.set_block(target + Vector3i.UP, BlockDB.DIRT)
	player._hit = _hit(target, Vector3i.UP)
	var occupied: Dictionary = player.placement_preview()
	h.check(not bool(occupied["valid"]), "an occupied destination is invalid")
	h.check(str(occupied["reason"]).contains("occupied"), "the occupied reason is explicit")
	h.check(bool(occupied["show"]), "an occupied destination is still previewed in red")
	ghost.update_preview(occupied)
	h.check(ghost.is_showing(), "the invalid ghost is shown at the occupied cell")
	h.check(not ghost.is_valid(), "the invalid ghost reports its invalid state")
	h.check(not player.place_selected(), "an occupied destination refuses placement")
	h.eq(world.get_block(target + Vector3i.UP), BlockDB.DIRT,
		"the refused placement leaves the occupied cell untouched")

	world.set_block(target + Vector3i.UP, BlockDB.AIR)
	player.teleport_to(Vector3(100.0, 100.0, 100.0))
	player._hit = _hit(Vector3i(100, 99, 100), Vector3i.UP)
	var inside: Dictionary = player.placement_preview()
	h.check(not bool(inside["valid"]), "a destination inside the body is invalid")
	h.eq(str(inside["reason"]), "inside you", "the body-collision reason is explicit")
	h.check(bool(inside["show"]), "the body-collision destination is still previewed in red")
	h.check(not player.place_selected(), "a destination inside the body refuses placement")

	player.teleport_to(Vector3(100.0, 100.0, 100.0))
	player._hit = _hit(Vector3i(8, 0, 8), Vector3i.DOWN)
	var below_world: Dictionary = player.placement_preview()
	h.check(not bool(below_world["valid"]), "a destination below the world is invalid")
	h.check(not bool(below_world["show"]), "the out-of-range destination hides the ghost")

	player._hit = _hit(Vector3i(47, 8, 8), Vector3i.RIGHT)
	var unloaded: Dictionary = player.placement_preview()
	h.check(not bool(unloaded["valid"]), "a destination in an unloaded chunk is invalid")
	h.check(not bool(unloaded["show"]), "the unloaded destination hides the ghost")
	ghost.update_preview(unloaded)
	h.check(not ghost.is_showing(), "the ghost hides beyond the loaded world")

	# No placeable item: an empty preview hides the ghost immediately.
	player.inventory.clear_slot(0)
	player.inventory.put_stack(0, {"item": ItemDB.APPLE, "count": 1})
	player.inventory.select(0)
	player._hit = _hit(target, Vector3i.UP)
	var no_item: Dictionary = player.placement_preview()
	h.check(no_item.is_empty(), "a food item has no block preview")
	ghost.update_preview(no_item)
	h.check(not ghost.is_showing(), "the ghost hides when no placeable item is selected")

	# Changing the selected block changes the ghost's real geometry.
	_select(player, BlockDB.GLASS)
	player._hit = _hit(target, Vector3i.UP)
	var glass: Dictionary = player.placement_preview()
	ghost.update_preview(glass)
	h.eq(ghost.preview_block(), BlockDB.GLASS, "the ghost follows the newly selected item")
	h.eq(ghost.preview_cell(), glass["cell"], "the ghost keeps the same destination cell")
	var glass_mesh: Mesh = ghost.preview_mesh()
	_select(player, BlockDB.STONE)
	var stone: Dictionary = player.placement_preview()
	ghost.update_preview(stone)
	h.eq(ghost.preview_block(), BlockDB.STONE, "the ghost follows the selection back to stone")
	h.check(glass_mesh != null and ghost.preview_mesh() != null,
		"both selected blocks produce a real preview mesh")

	player.queue_free()
	ghost.queue_free()


func _finish_scene() -> void:
	# The runner waits one frame before exiting; freeing the mesher-owned
	# resources explicitly keeps the leak report clean.
	_mesher = null
	_materials = null
	_library = null
