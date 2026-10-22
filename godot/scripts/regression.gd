extends SceneTree

const SCENARIO_PATH := "res://../prototypes/m17/shared/scenario.json"
const FIXTURE_PATH := "res://../prototypes/m17/shared/fixture/world.json"
const MAIN_SCRIPT := preload("res://scripts/main.gd")

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scenario_file := FileAccess.open(ProjectSettings.globalize_path(SCENARIO_PATH), FileAccess.READ)
	var fixture_file := FileAccess.open(ProjectSettings.globalize_path(FIXTURE_PATH), FileAccess.READ)
	check(scenario_file != null and fixture_file != null, "shared scenario and fixture exist")
	if scenario_file == null or fixture_file == null:
		finish()
		return
	var scenario: Dictionary = JSON.parse_string(scenario_file.get_as_text())
	var fixture: Dictionary = JSON.parse_string(fixture_file.get_as_text())
	var fixture_hashes: Dictionary = {}
	for chunk: Dictionary in fixture.chunks:
		fixture_hashes[Vector3i(int(chunk.coord[0]), 0, int(chunk.coord[2]))] = str(chunk.sha256)
	check(fixture.chunks.size() == 9, "shared fixture covers nine chunk coordinates")

	var app := Node3D.new()
	app.set_script(MAIN_SCRIPT)
	app.set("build_collisions", true)
	root.add_child(app)
	# Bound the integration test: generator caching must not turn the headless test
	# into an accidental multi-minute 9-chunk procedural-world benchmark.
	var smoke_timer := create_timer(25.0)
	var completed := false
	smoke_timer.timeout.connect(func():
		if not completed:
			failures.append("world fixture/mesh startup did not complete within 25 seconds")
			finish()
	)
	while app.get("voxel_world") == null or app.get("chunk_nodes").size() < 9:
		await process_frame
		if failures.size() > 0:
			return
	check(app.get("blocks").size() == 9, "loads the shared 16×16×16 blocks into the authoritative world")
	check(app.get("fixture_metrics").get("hash_checks", 0) == 9, "checks nine fixture SHA-256 digests")
	check(int(app.get("scenario").get("seed", -1)) == 17017, "loads the shared scenario seed")
	var world: VoxelWorld = app.get("voxel_world")
	check(world != null, "adopts fixture data through VoxelWorld")
	check(world.chunks.size() == 9, "creates nine authoritative logical chunks")
	for coord: Vector3i in world.chunks:
		check(fixture_hashes.has(coord), "preserves the logical fixture coordinate %s" % coord)
		check(app.get("chunk_nodes")[coord].get_node_or_null("ChunkMesh") != null, "builds the 16³ chunk mesh %s" % coord)
		check(app.get("chunk_nodes")[coord].get_node_or_null("ChunkCollision") != null, "builds collision for chunk %s" % coord)
	for material_id: int in [BlockDB.GRASS, BlockDB.DIRT, BlockDB.STONE, BlockDB.WATER]:
		check(app.get("materials").has(material_id), "creates visible %s shader" % BlockDB.name_of(material_id))

	check(world.get_block(Vector3i(-1, 7, 0)) != BlockDB.AIR, "reads a solid block at negative world X")
	check(world.get_block(Vector3i(-16, 7, 0)) != BlockDB.AIR, "floor maps x=-16 to chunk -1")
	check(world.get_block(Vector3i(-17, 7, 0)) == BlockDB.AIR, "floor maps x=-17 to unloaded chunk -2")
	var x_minus_one_chunks: Array = app.get("_affected_chunk_keys").call(Vector3i(-1, 3, 0))
	check(x_minus_one_chunks.has(Vector3i(-1, 0, 0)) and x_minus_one_chunks.has(Vector3i(0, 0, 0)),
		"negative x=-1 edge edit targets both adjacent chunks")
	var x_minus_sixteen_chunks: Array = app.get("_affected_chunk_keys").call(Vector3i(-16, 3, 0))
	check(x_minus_sixteen_chunks.has(Vector3i(-1, 0, 0)) and x_minus_sixteen_chunks.has(Vector3i(-2, 0, 0)),
		"negative x=-16 edge edit targets both adjacent chunks")

	# The shared fixture columns are not bitwise continuous across all slopes.
	# Pick a pair of adjacent solid boundary cells from the fixture itself.
	var boundary := _shared_solid_boundary(fixture)
	check(not boundary.is_empty(), "fixture includes at least one matching solid negative/positive boundary pair")
	if not boundary.is_empty():
		var position: Vector3i = boundary[0]
		var neighbour: Vector3i = boundary[1]
		var first_chunk := world.world_to_chunk(position)
		var second_chunk := world.world_to_chunk(neighbour)
		check(first_chunk == Vector3i(-1, 0, 0) and second_chunk == Vector3i(0, 0, 0), "cross-boundary edit spans chunks -1 and 0")
		var first_before: ArrayMesh = app.get("chunk_nodes")[first_chunk].get_node("ChunkMesh").mesh
		var second_before: ArrayMesh = app.get("chunk_nodes")[second_chunk].get_node("ChunkMesh").mesh
		var previous: int = world.get_block(position)
		check(world.set_block(position, BlockDB.AIR), "breaks the negative-side shared boundary block")
		# The fixture renderer has its own edit entry point; invoke it after the
		# logical-world edit so both neighbouring mesh nodes are rebuilt.
		app.get("_set_fixture_block").call(position, BlockDB.AIR)
		check(world.get_block(position) == BlockDB.AIR, "authoritative block storage applies the edit")
		check(world.get_block(neighbour) != BlockDB.AIR, "preserves the adjacent boundary block")
		var first_after: ArrayMesh = app.get("chunk_nodes")[first_chunk].get_node("ChunkMesh").mesh
		var second_after: ArrayMesh = app.get("chunk_nodes")[second_chunk].get_node("ChunkMesh").mesh
		check(first_before != first_after, "refreshes the edited negative chunk mesh")
		check(second_before != second_after, "refreshes the adjacent positive chunk mesh")
		check(world.edits.has(position) and world.edits[position] == BlockDB.AIR, "records edits in the logical edit overlay")
		app.get("player").global_position = Vector3(8.5, 12.0, 8.5)
		check(app.get("_player_intersects").call(Vector3i(8, 12, 8)),
			"player-intersection guard reports a cell containing the player")
		if previous == BlockDB.WATER:
			check(true, "boundary edit exercised water adjacency")
	else:
		failures.append("could not locate a shared solid boundary cell to break")

	# Remove the direct script deadline and quit before slow unrelated project tests.
	completed = true
	app.free()
	finish()


func _shared_solid_boundary(fixture: Dictionary) -> Array:
	var chunks: Dictionary = {}
	for chunk: Dictionary in fixture.chunks:
		chunks[Vector3i(int(chunk.coord[0]), 0, int(chunk.coord[2]))] = str(chunk.cells)
	var left: String = chunks.get(Vector3i(-1, 0, 0), "")
	var right: String = chunks.get(Vector3i(0, 0, 0), "")
	for y in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var index := 15 + ChunkData.SIZE * (z + ChunkData.SIZE * y)
			var other_index := ChunkData.SIZE * (z + ChunkData.SIZE * y)
			var a := int(left.unicode_at(index)) - 48
			var b := int(right.unicode_at(other_index)) - 48
			if a > 0 and a < 4 and b > 0 and b < 4:
				return [Vector3i(-1, y, z), Vector3i(0, y, z)]
	return []


func check(condition: bool, description: String) -> void:
	assertions += 1
	if condition:
		print("M17_ASSERT_PASS %s" % description)
	else:
		failures.append(description)
		push_error("M17_ASSERT_FAIL %s" % description)


func finish() -> void:
	if failures.is_empty():
		print("M17_REGRESSION_PASS assertions=%d" % assertions)
		quit(0)
	else:
		for failure: String in failures:
			print("M17_REGRESSION_FAIL %s" % failure)
		quit(1)
