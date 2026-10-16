extends RefCounted

## Streaming determinism.
##
## The logical world and the derived geometry must be a pure function of the seed
## and the set of streamed chunk coordinates -- not of the frame budgets, the
## order the chunks happened to load in, or how the work was split across frames.
## These tests pin both halves down with fingerprints, so a regression shows up as
## a hash mismatch instead of an occasional visual difference.


func name() -> String:
	return "streaming determinism"


var _library: TextureLibrary
var _mesher: ChunkMesher


func _setup() -> void:
	if _mesher != null:
		return
	_library = TextureLibrary.new()
	_library.load_all()
	_mesher = ChunkMesher.new(_library, VoxelMaterials.new(_library))


## Streams one world to completion around a fixed focus point with the given
## per-frame budgets.  The streamer is attached to the scene root so it behaves
## exactly like the streamer in the running game.
func _stream(radius: int, vertical: int, generation_budget: int, mesh_budget: int) -> ChunkStreamer:
	var world := VoxelWorld.new(17017)
	var streamer := ChunkStreamer.new()
	streamer.render_radius = radius
	streamer.vertical_radius = vertical
	streamer.generation_budget = generation_budget
	streamer.mesh_budget = mesh_budget
	streamer.focus_node = null
	streamer.setup(world, _mesher)
	# The engine must not drive the streamer itself: this test owns the frame loop.
	streamer.set_process(false)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(streamer)
	streamer.position = Vector3(8.5, 70.0, 8.5)
	streamer.focus_at(streamer.position)
	var guard := 0
	while not streamer.is_settled() and guard < 4000:
		streamer._process(0.016)
		guard += 1
	return streamer


## Detaches a streamer built by `_stream`.  Views are freed immediately rather
## than through the deferred queue so the headless run exits without leak noise.
func _release(streamer: ChunkStreamer) -> void:
	for child in streamer.get_children():
		child.free()
	var parent := streamer.get_parent()
	if parent != null:
		parent.remove_child(streamer)
	streamer.free()


func run(h: TestHarness) -> void:
	_setup()
	h.check(_mesher != null, "creates a mesher")

	# 1) A coarse-budget stream and a fine-budget stream must end up with exactly
	# the same logical world, even though they generate and mesh different chunks
	# in different frames.
	var coarse := _stream(3, 2, 8, 3)
	var fine := _stream(3, 2, 1, 1)
	var coarse_report := coarse.report()
	var fine_report := fine.report()

	h.greater(float(coarse_report["wanted"]), 60.0, "the coarse stream loaded a real region (%d chunks)" % int(coarse_report["wanted"]))
	h.eq(int(coarse_report["wanted"]), int(fine_report["wanted"]), "both streams want the same chunk set")
	h.eq(int(coarse_report["loaded"]), int(fine_report["loaded"]), "both streams loaded the same number of chunks")
	h.eq(coarse.world.fingerprint(), fine.world.fingerprint(), "the logical world is identical for both batch sizes")
	h.eq(int(coarse_report["faces_hash"]), int(fine_report["faces_hash"]),
		"the streamed geometry is identical for both batch sizes (%d vs %d faces)" % [int(coarse_report["faces"]), int(fine_report["faces"])])

	# The two streams must agree chunk for chunk, not just in aggregate.
	var mismatches := 0
	for coord: Vector3i in VoxelWorld.sorted_coords(coarse.face_counts):
		if int(coarse.face_counts[coord]) != int(fine.face_counts.get(coord, -1)):
			mismatches += 1
	h.eq(mismatches, 0, "no single chunk differs between the two batch sizes")

	# 2) Every wanted chunk must be meshed, and no unwanted chunk may be.	h.eq(fine.face_counts.size(), int(fine_report["wanted"]), "every wanted chunk is meshed exactly once")
	var face_total := 0
	for coord: Vector3i in fine.face_counts:
		face_total += int(fine.face_counts[coord])
	h.eq(face_total, int(fine_report["faces"]), "the reported face total matches the per-chunk geometry")
	h.eq(int(fine_report["unloaded"]), 0, "nothing was unloaded while filling a fixed focus")

	# 3) Clearing the streamer releases geometry but keeps the world usable.
	coarse.clear()
	h.eq(coarse.loaded_count(), 0, "clear() drops every loaded chunk")
	h.eq(coarse.face_counts.size(), 0, "clear() drops every derived face count")

	# 4) The same world generated in two different orders, without any streaming,
	# must produce the same voxels.  This is the generator half of the contract.
	var forward := VoxelWorld.new(17017)
	var backward := VoxelWorld.new(17017)
	var coords: Array = []
	for chunk_y in range(2, 7):
		for chunk_z in range(-3, 4):
			for chunk_x in range(-3, 4):
				coords.append(Vector3i(chunk_x, chunk_y, chunk_z))
	for coord: Vector3i in coords:
		forward.ensure_chunk(coord)
	for index in range(coords.size() - 1, -1, -1):
		backward.ensure_chunk(coords[index])
	h.eq(forward.fingerprint(), backward.fingerprint(), "generation order does not change the voxels")

	# 5) A fingerprint must be sensitive to actual change, or the tests above
	# would pass on a constant.
	var mutated := VoxelWorld.new(17017)
	mutated.ensure_chunk(Vector3i(0, 4, 0))
	var before := mutated.fingerprint()
	mutated.set_block(Vector3i(8, 70, 8), BlockDB.STONE)
	h.check(mutated.fingerprint() != before, "the world fingerprint reacts to an edit")

	# 6) Every meshed chunk owns exactly one view node, and tearing the streamer
	# down must leave nothing behind.
	h.eq(fine.get_child_count(), int(fine_report["wanted"]), "every wanted chunk owns one view node")
	_release(fine)
	_release(coarse)
	h.finish()