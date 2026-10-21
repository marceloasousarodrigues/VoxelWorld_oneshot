extends RefCounted

## Chunk-streamer lifecycle with background (threaded) generation.
##
## Generation is a pure function of the seed and the chunk coordinate, so moving
## it to a worker thread must not change *which* chunks end up loaded.  These
## tests pin the three contracts that a background generator can break:
##
## - the number of generated-but-not-yet-adopted chunks stays bounded, so the
##   main thread is never flooded with results;
## - a result for a chunk that left the wanted set while it was being generated
##   is dropped instead of being adopted outside the streamed region;
## - `clear()` tears the worker down and the streamer can be restarted.

var _library: TextureLibrary
var _mesher: ChunkMesher


func name() -> String:
	return "streamer lifecycle (threaded generation)"


func _setup() -> void:
	if _mesher != null:
		return
	_library = TextureLibrary.new()
	_library.load_all()
	_mesher = ChunkMesher.new(_library, VoxelMaterials.new(_library))


func _make_streamer(radius: int = 2, version: int = WorldGen.CURRENT_VERSION) -> ChunkStreamer:
	var world := VoxelWorld.new(17017, version)
	var streamer := ChunkStreamer.new()
	streamer.render_radius = radius
	streamer.vertical_radius = 1
	streamer.threaded_meshing = true
	streamer.threaded_generation = true
	streamer.setup(world, _mesher)
	# The test owns the frame loop, so the engine must not drive the streamer.
	streamer.set_process(false)
	(Engine.get_main_loop() as SceneTree).root.add_child(streamer)
	streamer.position = Vector3(8.5, 70.0, 8.5)
	streamer.focus_at(streamer.position)
	return streamer


## Steps the streamer until it is settled with no build in flight, giving the
## worker threads a slice of wall clock between frames.
func _pump(streamer: ChunkStreamer, frames: int = 6000) -> int:
	var guard := 0
	while guard < frames:
		streamer._process(0.016)
		OS.delay_usec(300)
		guard += 1
		if streamer.is_settled() and int(streamer.report()["meshes_in_flight"]) == 0:
			break
	return guard


func _release(streamer: ChunkStreamer) -> void:
	for child in streamer.get_children():
		child.free()
	var parent := streamer.get_parent()
	if parent != null:
		parent.remove_child(streamer)
	streamer.free()


func _test_in_flight_is_bounded(h: TestHarness) -> void:
	var streamer := _make_streamer(2)
	streamer.generation_budget = 64
	streamer.max_generation_in_flight = 4
	streamer._process(0.016)
	var in_flight := int(streamer.report()["generation_in_flight"])
	h.check(in_flight > 0, "generation work is handed to the background worker")
	h.less(float(in_flight), 5.0, "generation in flight never exceeds its cap (%d)" % in_flight)
	_pump(streamer)
	h.eq(int(streamer.report()["generation_in_flight"]), 0,
		"the in-flight count returns to zero once the region is settled")
	h.eq(streamer.loaded_count(), int(streamer.report()["wanted"]),
		"every wanted chunk is loaded after a background stream")
	_release(streamer)


## A generation result that arrives after its chunk left the wanted set must be
## discarded: adopting it would put a loaded chunk outside the streamed region
## (and, at the edge, outside the fogged area) until the next focus move.
func _test_stale_generation_is_not_adopted(h: TestHarness) -> void:
	var streamer := _make_streamer(2)
	streamer.generation_budget = 64
	streamer.max_generation_in_flight = 64
	streamer._process(0.016)
	h.check(int(streamer.report()["generation_in_flight"]) > 0,
		"the first window is being generated when the focus moves")
	# Move far enough that the whole first window is outside the new wanted set.
	streamer.position = Vector3(5008.5, 70.0, 5008.5)
	streamer.focus_at(streamer.position)
	_pump(streamer)
	var report := streamer.report()
	h.greater(float(report["loaded"]), 0.0, "the new region streamed in")
	h.eq(int(report["loaded"]), int(report["wanted"]),
		"only wanted chunks are loaded; stale generation results are dropped")
	h.eq(int(report["generation_in_flight"]), 0, "the dropped results leave nothing in flight")
	_release(streamer)


func _test_clear_restarts_the_worker(h: TestHarness) -> void:
	var streamer := _make_streamer(1)
	_pump(streamer)
	h.greater(float(streamer.loaded_count()), 0.0, "the region streamed in before the teardown")
	streamer.clear()
	h.eq(streamer.loaded_count(), 0, "clear() unloads every chunk")
	h.eq(streamer.view_count(), 0, "clear() drops every view")
	streamer.focus_at(streamer.position)
	_pump(streamer)
	h.eq(streamer.loaded_count(), int(streamer.report()["wanted"]),
		"the streamer streams again after clear() (the worker was restarted)")
	_release(streamer)


## A loaded historical save must keep streaming its recorded generator version,
## not the current version.  This catches the latent `WorldGen.new(seed)` default
## in the background generation worker.
func _test_generation_uses_world_version(h: TestHarness) -> void:
	for version: int in [3, 5]:
		var streamer := _make_streamer(2, version)
		streamer.generation_budget = 64
		_pump(streamer)
		h.eq(streamer.world.generator.terrain_version, version,
			"the streamer world keeps its recorded generator version %d" % version)
		h.eq(streamer._gen_worker_gen.terrain_version, version,
			"the background generator uses the world's recorded version %d" % version)
		var coords := VoxelWorld.sorted_coords(streamer.world.chunks)
		h.greater(float(coords.size()), 0.0, "the v%d world streamed chunks" % version)
		var coord: Vector3i = coords[0]
		var reference := VoxelWorld.new(17017, version)
		reference.ensure_chunk(coord)
		var streamed: ChunkData = streamer.world.get_chunk(coord)
		var expected: ChunkData = reference.get_chunk(coord)
		h.eq(streamed.blocks, expected.blocks,
			"streamed v%d chunk blocks match synchronous generation" % version)
		h.eq(streamed.biomes, expected.biomes,
			"streamed v%d chunk biomes match synchronous generation" % version)
		_release(streamer)


func run(h: TestHarness) -> void:
	_setup()
	h.check(_mesher != null, "creates a mesher")
	_test_in_flight_is_bounded(h)
	_test_stale_generation_is_not_adopted(h)
	_test_clear_restarts_the_worker(h)
	_test_generation_uses_world_version(h)
	h.finish()
