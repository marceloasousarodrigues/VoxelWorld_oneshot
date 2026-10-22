extends RefCounted

## Block-edit rebuild regressions.
##
## These tests drive the *authoritative* edit path and then rebuild only the
## chunks the world says are stale -- exactly what the streamer does -- so a
## missing invalidation shows up as missing rendered faces and missing collision
## triangles, not merely as a dirty flag.  One case uses the real threaded
## `ChunkStreamer` to exercise edits that race a rebuild already in flight.

const EPS := 0.001

var _library: TextureLibrary
var _materials: VoxelMaterials
var _mesher: ChunkMesher


func name() -> String:
	return "edit rebuild and collision"


func _setup() -> void:
	if _mesher != null:
		return
	_library = TextureLibrary.new()
	_library.load_all()
	_materials = VoxelMaterials.new(_library)
	_mesher = ChunkMesher.new(_library, _materials)


func _make_chunk(world: VoxelWorld, coord: Vector3i) -> ChunkData:
	var chunk := ChunkData.new(coord)
	chunk.generated = true
	world.adopt_chunk(chunk)
	return chunk


func _world_cell(chunk_coord: Vector3i, local: Vector3i) -> Vector3i:
	return VoxelWorld.chunk_origin(chunk_coord) + local


## Rebuilds exactly the chunks whose derived state the world has invalidated,
## recording the new geometry as the "live" mesh.  This is the streamer's
## contract in miniature: a chunk that was not invalidated keeps its old mesh.
func _rebuild_dirty(world: VoxelWorld, live: Dictionary) -> int:
	var rebuilt := 0
	for coord: Vector3i in VoxelWorld.sorted_coords(world.chunks):
		var chunk: ChunkData = world.chunks[coord]
		if not chunk.mesh_dirty and not chunk.collision_dirty:
			continue
		live[coord] = _mesher.build(chunk, world)
		chunk.mesh_dirty = false
		chunk.collision_dirty = false
		rebuilt += 1
	return rebuilt


func _settled(chunk: ChunkData) -> void:
	chunk.mesh_dirty = false
	chunk.collision_dirty = false


# --- geometry probes ------------------------------------------------------

func _triangle_matches(a: Vector3, b: Vector3, c: Vector3, centre: Vector3, outward: Vector3) -> bool:
	# All three vertices must lie on the face's plane.
	if absf((a - centre).dot(outward)) > EPS:
		return false
	if absf((b - centre).dot(outward)) > EPS:
		return false
	if absf((c - centre).dot(outward)) > EPS:
		return false
	# ... and the triangle must be part of the 1x1 quad centred there, not a
	# coplanar neighbour.
	if ((a + b + c) / 3.0 - centre).length() > 0.6:
		return false
	# Godot front faces are wound so the geometric normal points into the solid.
	return (b - a).cross(c - a).dot(outward) < 0.0


func _render_face_present(mesh: ArrayMesh, centre: Vector3, outward: Vector3) -> bool:
	if mesh == null:
		return false
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var i := 0
		while i + 2 < indices.size():
			var ia := int(indices[i])
			var ib := int(indices[i + 1])
			var ic := int(indices[i + 2])
			var stored: Vector3 = (normals[ia] + normals[ib] + normals[ic]).normalized()
			if _triangle_matches(vertices[ia], vertices[ib], vertices[ic], centre, outward) \
					and stored.dot(outward) > 0.99:
				return true
			i += 3
	return false


func _collision_face_present(mesh: ArrayMesh, centre: Vector3, outward: Vector3) -> bool:
	if mesh == null:
		return false
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var i := 0
		while i + 2 < indices.size():
			if _triangle_matches(vertices[int(indices[i])], vertices[int(indices[i + 1])],
					vertices[int(indices[i + 2])], centre, outward):
				return true
			i += 3
	return false


func _triangle_count(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var count := 0
	for surface in mesh.get_surface_count():
		count += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return count


func _has_triangle_on_axis_plane(mesh: ArrayMesh, axis: int, value: float) -> bool:
	if mesh == null:
		return false
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var i := 0
		while i + 2 < indices.size():
			var a := vertices[int(indices[i])]
			var b := vertices[int(indices[i + 1])]
			var c := vertices[int(indices[i + 2])]
			if absf(a[axis] - value) <= EPS and absf(b[axis] - value) <= EPS and absf(c[axis] - value) <= EPS:
				return true
			i += 3
	return false


func _face_centre(cell: Vector3i, outward: Vector3i) -> Vector3:
	return Vector3(cell) + Vector3(0.5, 0.5, 0.5) + Vector3(outward) * 0.5


# --- threaded streamer ----------------------------------------------------

func _pump(streamer: ChunkStreamer, world: VoxelWorld, frames: int = 2000) -> int:
	var guard := 0
	var minimum := 4
	while guard < frames:
		streamer._process(0.016)
		OS.delay_usec(250)
		guard += 1
		if guard < minimum:
			continue
		if not streamer.is_settled() or streamer.queued_count() > 0:
			continue
		if int(streamer.report()["meshes_in_flight"]) > 0:
			continue
		var dirty := false
		for coord: Vector3i in world.chunks:
			if (world.chunks[coord] as ChunkData).mesh_dirty:
				dirty = true
				break
		if not dirty:
			break
	return guard


## A controlled 3x3 chunk region (one vertical layer) adopted before setup, so
## the streamer only renders the geometry this test puts in it.
func _controlled_stream() -> Dictionary:
	var world := VoxelWorld.new(17017)
	var coords: Array[Vector3i] = []
	for chunk_z in range(-1, 2):
		for chunk_x in range(-1, 2):
			coords.append(Vector3i(chunk_x, 0, chunk_z))
	for coord: Vector3i in coords:
		_make_chunk(world, coord)
	var streamer := ChunkStreamer.new()
	streamer.render_radius = 1
	streamer.vertical_radius = 0
	streamer.generation_budget = 0
	streamer.mesh_budget = 4
	streamer.threaded_meshing = true
	streamer.setup(world, _mesher)
	streamer.set_process(false)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(streamer)
	streamer.position = Vector3(8.5, 8.5, 8.5)
	streamer.focus_at(streamer.position)
	return {"world": world, "streamer": streamer}


func _release(streamer: ChunkStreamer) -> void:
	for child in streamer.get_children():
		child.free()
	var parent := streamer.get_parent()
	if parent != null:
		parent.remove_child(streamer)
	streamer.free()


func _view_mesh(streamer: ChunkStreamer, coord: Vector3i, name: String) -> ArrayMesh:
	var view: Node3D = streamer.views.get(coord)
	if view == null:
		return null
	var instance := view.get_node_or_null(name)
	if instance is MeshInstance3D:
		return (instance as MeshInstance3D).mesh
	return null


func _view_collision_faces(streamer: ChunkStreamer, coord: Vector3i) -> PackedVector3Array:
	var view: Node3D = streamer.views.get(coord)
	if view == null:
		return PackedVector3Array()
	var body := view.get_node_or_null("Collision")
	if body == null:
		return PackedVector3Array()
	var shape_node := body.get_child(0) as CollisionShape3D
	if shape_node == null or not (shape_node.shape is ConcavePolygonShape3D):
		return PackedVector3Array()
	return (shape_node.shape as ConcavePolygonShape3D).get_faces()


func _collision_faces_have(faces: PackedVector3Array, centre: Vector3, outward: Vector3) -> bool:
	var i := 0
	while i + 2 < faces.size():
		if _triangle_matches(faces[i], faces[i + 1], faces[i + 2], centre, outward):
			return true
		i += 3
	return false


# --- tests ----------------------------------------------------------------

## Breaking a fully enclosed block must expose exactly its six neighbours and
## add matching collision, while leaving the rest of the terrain culled.
func _test_interior_break(h: TestHarness) -> void:
	var world := VoxelWorld.new(17017)
	var chunk := _make_chunk(world, Vector3i.ZERO)
	for local_y in range(7, 10):
		for local_z in range(7, 10):
			for local_x in range(7, 10):
				chunk.blocks[ChunkData.cell_index(local_x, local_y, local_z)] = BlockDB.STONE
	# A separate pair of touching blocks, away from the hole, pins face culling:
	# ten exposed faces, never the shared interior one.
	chunk.blocks[ChunkData.cell_index(2, 5, 2)] = BlockDB.STONE
	chunk.blocks[ChunkData.cell_index(3, 5, 2)] = BlockDB.STONE
	var before := _mesher.build(chunk, world)
	h.eq(int(before["faces"]), 64, "the solid cube and the adjacent pair emit only their outer faces")
	_settled(chunk)

	var target := Vector3i(8, 8, 8)
	h.check(world.set_block(target, BlockDB.AIR), "the enclosed block can be broken")
	h.check(chunk.mesh_dirty, "the edited chunk is invalidated")
	var live := {}
	h.eq(_rebuild_dirty(world, live), 1, "exactly the edited chunk needs a rebuild")
	var after: Dictionary = live[Vector3i.ZERO]
	h.eq(int(after["faces"]), 70, "breaking an enclosed block adds six exposed faces")
	h.eq(_triangle_count(after["collision"]), 140, "collision gains two triangles per exposed face")

	var missing := 0
	for direction: Vector3i in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP,
			Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		var centre := _face_centre(target, direction)
		var outward := Vector3(-direction)
		if not _render_face_present(after["mesh"], centre, outward):
			missing += 1
		if not _collision_face_present(after["collision"], centre, outward):
			missing += 1
	h.eq(missing, 0, "all six newly exposed faces exist in the render mesh and collision")
	h.eq(world.get_block(target), BlockDB.AIR, "authoritative data agrees with the visible hole")

	# Face culling must still hold for the untouched adjacent pair: the plane
	# between two intact neighbours carries no triangle at all.
	h.check(not _has_triangle_on_axis_plane(after["mesh"], 0, 3.0),
		"intact adjacent blocks keep their shared face culled")
	h.check(not _has_triangle_on_axis_plane(after["collision"], 0, 3.0),
		"culled internal faces add no collision either")


## An edit on any of the six chunk-boundary planes must invalidate the chunk on
## the other side, because that chunk gains or loses the shared face.
func _test_boundary_break(h: TestHarness) -> void:
	var directions := {
		"PX": Vector3i.RIGHT, "NX": Vector3i.LEFT,
		"PY": Vector3i.UP, "NY": Vector3i.DOWN,
		"PZ": Vector3i.BACK, "NZ": Vector3i.FORWARD,
	}
	for label: String in directions:
		var direction: Vector3i = directions[label]
		var world := VoxelWorld.new(17017)
		var edited_coord := Vector3i.ZERO
		var neighbour_coord := direction
		var edited := _make_chunk(world, edited_coord)
		var neighbour := _make_chunk(world, neighbour_coord)
		var edited_local := Vector3i(8, 8, 8)
		var neighbour_local := Vector3i(8, 8, 8)
		if direction.x != 0:
			edited_local.x = 15 if direction.x > 0 else 0
			neighbour_local.x = 0 if direction.x > 0 else 15
		elif direction.y != 0:
			edited_local.y = 15 if direction.y > 0 else 0
			neighbour_local.y = 0 if direction.y > 0 else 15
		else:
			edited_local.z = 15 if direction.z > 0 else 0
			neighbour_local.z = 0 if direction.z > 0 else 15
		edited.blocks[ChunkData.cell_index(edited_local.x, edited_local.y, edited_local.z)] = BlockDB.STONE
		neighbour.blocks[ChunkData.cell_index(neighbour_local.x, neighbour_local.y, neighbour_local.z)] = BlockDB.STONE
		var live := {
			edited_coord: _mesher.build(edited, world),
			neighbour_coord: _mesher.build(neighbour, world),
		}
		h.eq(int((live[edited_coord] as Dictionary)["faces"]), 5, "%s: the shared face starts culled on the edited side" % label)
		h.eq(int((live[neighbour_coord] as Dictionary)["faces"]), 5, "%s: the shared face starts culled on the neighbour side" % label)
		_settled(edited)
		_settled(neighbour)

		var target := _world_cell(edited_coord, edited_local)
		h.check(world.set_block(target, BlockDB.AIR), "%s: the boundary block can be broken" % label)
		_rebuild_dirty(world, live)

		var edited_result: Dictionary = live[edited_coord]
		var neighbour_result: Dictionary = live[neighbour_coord]
		h.eq(int(edited_result["faces"]), 0, "%s: the broken block leaves no geometry" % label)
		h.check(edited_result["collision"] == null, "%s: the broken block leaves no collision" % label)
		h.eq(int(neighbour_result["faces"]), 6, "%s: the neighbouring chunk gains the newly exposed face" % label)
		# Meshes are chunk-local; the view node carries the chunk origin.
		var centre := _face_centre(target, direction) - Vector3(VoxelWorld.chunk_origin(neighbour_coord))
		var outward := Vector3(-direction)
		h.check(_render_face_present(neighbour_result["mesh"], centre, outward),
			"%s: the exposed neighbour face is present in the render mesh" % label)
		h.check(_collision_face_present(neighbour_result["collision"], centre, outward),
			"%s: the exposed neighbour face is present in collision" % label)
		h.eq(_triangle_count(neighbour_result["collision"]), 12,
			"%s: the neighbour's collision holds all six faces" % label)
		h.eq(world.get_block(target), BlockDB.AIR, "%s: authoritative data records the break" % label)


## The real threaded streamer: an edit at a +Z chunk boundary must rebuild the
## chunk on the other side, even though the worker was idle at the time.
func _test_threaded_boundary_rebuild(h: TestHarness) -> void:
	var scene := _controlled_stream()
	var world: VoxelWorld = scene["world"]
	var streamer: ChunkStreamer = scene["streamer"]
	_pump(streamer, world)

	var edited_coord := Vector3i.ZERO
	var neighbour_coord := Vector3i(0, 0, 1)
	var edited := world.get_chunk(edited_coord)
	var neighbour := world.get_chunk(neighbour_coord)
	edited.blocks[ChunkData.cell_index(8, 8, 15)] = BlockDB.STONE
	neighbour.blocks[ChunkData.cell_index(8, 8, 0)] = BlockDB.STONE
	edited.mark_dirty()
	neighbour.mark_dirty()
	_pump(streamer, world)
	h.eq(int(streamer.face_counts.get(edited_coord, -1)), 5, "streamed shared face is culled on the edited side")
	h.eq(int(streamer.face_counts.get(neighbour_coord, -1)), 5, "streamed shared face is culled on the neighbour side")

	var target := Vector3i(8, 8, 15)
	h.check(world.set_block(target, BlockDB.AIR), "the streamed +Z boundary block can be broken")
	_pump(streamer, world)

	h.eq(int(streamer.face_counts.get(edited_coord, -1)), 0, "the streamed edited chunk drops the broken block")
	h.eq(int(streamer.face_counts.get(neighbour_coord, -1)), 6,
		"the threaded streamer rebuilt the +Z neighbour after the edit")
	var centre := _face_centre(target, Vector3i.BACK) - Vector3(VoxelWorld.chunk_origin(neighbour_coord))
	var outward := Vector3.FORWARD
	h.check(_render_face_present(_view_mesh(streamer, neighbour_coord, "Solid"), centre, outward),
		"the live +Z neighbour mesh contains the exposed face")
	h.check(_collision_faces_have(_view_collision_faces(streamer, neighbour_coord), centre, outward),
		"the live +Z neighbour collision contains the exposed face")
	h.eq(world.get_block(target), BlockDB.AIR, "the streamed world records the broken block")
	_release(streamer)


## Two edits in the same chunk while its first rebuild is still in flight must
## both survive, and the final rendered/collision geometry must agree with the
## authoritative voxels.
func _test_consecutive_edits(h: TestHarness) -> void:
	var scene := _controlled_stream()
	var world: VoxelWorld = scene["world"]
	var streamer: ChunkStreamer = scene["streamer"]
	_pump(streamer, world)

	var edited_coord := Vector3i.ZERO
	var neighbour_coord := Vector3i(0, 0, 1)
	var edited := world.get_chunk(edited_coord)
	var neighbour := world.get_chunk(neighbour_coord)
	for x in range(5, 8):
		edited.blocks[ChunkData.cell_index(x, 8, 15)] = BlockDB.STONE
		neighbour.blocks[ChunkData.cell_index(x, 8, 0)] = BlockDB.STONE
	edited.mark_dirty()
	neighbour.mark_dirty()
	_pump(streamer, world)

	var first := Vector3i(6, 8, 15)
	var second := Vector3i(5, 8, 15)
	h.check(world.set_block(first, BlockDB.AIR), "the first of two quick edits is applied")
	streamer._process(0.016)
	OS.delay_usec(250)
	h.greater(float(streamer.report()["meshes_in_flight"]), 0.0,
		"the first edit's rebuild is genuinely in flight before the second edit")
	h.check(world.set_block(second, BlockDB.AIR), "the second edit is applied before the rebuild completes")
	_pump(streamer, world)

	h.eq(world.get_block(first), BlockDB.AIR, "the first edit survives the race")
	h.eq(world.get_block(second), BlockDB.AIR, "the second edit survives the race")
	var mismatches := 0
	for coord: Vector3i in [edited_coord, neighbour_coord]:
		var fresh := _mesher.build(world.get_chunk(coord), world)
		if int(streamer.face_counts.get(coord, -1)) != int(fresh["faces"]):
			mismatches += 1
		var live_mesh := _view_mesh(streamer, coord, "Solid")
		var live_vertices := 0
		if live_mesh != null:
			for surface in live_mesh.get_surface_count():
				live_vertices += (live_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var fresh_vertices := 0
		if fresh["mesh"] != null:
			for surface in (fresh["mesh"] as ArrayMesh).get_surface_count():
				fresh_vertices += ((fresh["mesh"] as ArrayMesh).surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if live_vertices != fresh_vertices:
			mismatches += 1
	h.eq(mismatches, 0, "rendered geometry matches a fresh build after consecutive edits")
	var centre := _face_centre(first, Vector3i.BACK) - Vector3(VoxelWorld.chunk_origin(neighbour_coord))
	h.check(_collision_faces_have(_view_collision_faces(streamer, neighbour_coord), centre, Vector3.FORWARD),
		"the neighbour's collision reflects the edit that raced the rebuild")
	_release(streamer)


## A pending threaded build must not outlive a change to its neighbour set: when
## a neighbour is unloaded while a build that culled against it is still in
## flight, the collected result is stale and the chunk must be rebuilt.
func _test_pending_build_survives_neighbour_unload(h: TestHarness) -> void:
	var scene := _controlled_stream()
	var world: VoxelWorld = scene["world"]
	var streamer: ChunkStreamer = scene["streamer"]
	_pump(streamer, world)
	streamer.generation_budget = 8

	var edited_coord := Vector3i.ZERO
	var neighbour_coord := Vector3i(0, 0, 1)
	var edited := world.get_chunk(edited_coord)
	# A solid block on the +Z border, its +Z face culled by the neighbour's block.
	edited.blocks[ChunkData.cell_index(8, 8, 15)] = BlockDB.STONE
	world.get_chunk(neighbour_coord).blocks[ChunkData.cell_index(8, 8, 0)] = BlockDB.STONE
	edited.mark_dirty()
	world.get_chunk(neighbour_coord).mark_dirty()
	_pump(streamer, world)
	h.eq(int(streamer.face_counts.get(edited_coord, -1)), 5,
		"the border block starts with its +Z face culled by the neighbour")

	# Dirty the chunk with an unrelated interior edit, start a build that still
	# sees the neighbour, then move the focus so the neighbour leaves the streamed
	# set while that build is in flight.
	world.set_block(Vector3i(2, 5, 5), BlockDB.STONE)
	streamer._process(0.016)
	OS.delay_usec(250)
	h.greater(float(streamer.report()["meshes_in_flight"]), 0.0,
		"the chunk's rebuild is genuinely in flight when the neighbour unloads")
	streamer.position = Vector3(8.5, 8.5, -8.0)
	streamer.focus_at(streamer.position)
	h.check(not world.has_chunk(neighbour_coord), "the neighbour leaves the loaded set")
	_pump(streamer, world)

	var fresh := _mesher.build(world.get_chunk(edited_coord), world)
	h.eq(int(streamer.face_counts.get(edited_coord, -1)), int(fresh["faces"]),
		"the chunk was rebuilt for the neighbour-less world (stale build discarded)")
	var centre := _face_centre(Vector3i(8, 8, 15), Vector3i.BACK)
	h.check(_render_face_present(_view_mesh(streamer, edited_coord, "Solid"), centre, Vector3.BACK),
		"the border block's exposed +Z face appears after the neighbour unloads")
	h.check(_collision_faces_have(_view_collision_faces(streamer, edited_coord), centre, Vector3.BACK),
		"the border block's collision appears after the neighbour unloads")
	_release(streamer)


func run(h: TestHarness) -> void:
	_setup()
	h.check(_mesher != null, "creates a mesher")
	_test_interior_break(h)
	_test_boundary_break(h)
	_test_threaded_boundary_rebuild(h)
	_test_consecutive_edits(h)
	_test_pending_build_survives_neighbour_unload(h)
	h.finish()
