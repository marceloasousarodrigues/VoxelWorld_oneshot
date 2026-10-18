class_name ChunkStreamer
extends Node3D

## Streams logical chunks in and out around the player and keeps their derived
## render and collision meshes in sync.
##
## Ordering guarantees
## - Generation is nearest-first and frame-budgeted, so the world fills in from
##   the player outwards and never stall a frame.
## - A chunk is only meshed once every neighbour that is *going to load* either
##   is loaded or falls outside the wanted set.  Without that rule the border of
##   every chunk would be meshed twice while its neighbours stream in.
## - A chunk is only unloaded when it leaves the wanted set, so edits and fluid
##   state in the loaded region always survive.
##
## The streamer never writes block data; `VoxelWorld` stays authoritative and the
## streamer only observes it.

const SIZE := ChunkData.SIZE
const FACE_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Horizontal streaming radius in chunks (configurable render distance).
@export var render_radius := 4
## Vertical streaming radius in chunks around the player's chunk column.
@export var vertical_radius := 4
## Upper bounds on per-frame streaming work.
@export var generation_budget := 8
@export var generation_millisecond_budget := 6.0
@export var mesh_budget := 3
@export var mesh_millisecond_budget := 8.0
## When true the expensive mesh build runs on a dedicated worker thread; the main
## thread only snapshots the input (when a chunk's neighbours are final) and
## attaches finished meshes.  Set false for the synchronous path used by tests.
@export var threaded_meshing := true
## Upper bound on submitted-but-unattached mesh jobs.  The worker builds one at a
## time, so this only bounds the queue depth.
@export var max_mesh_in_flight := 4
## When false a fresh chunk streams without generating collision geometry.
@export var collision_enabled := true

## The node the streamer keeps its loaded region centred on.  When null the
## streamer follows its own world position.
var focus_node: Node3D = null

var world: VoxelWorld
var mesher: ChunkMesher
var views: Dictionary = {}
var stats := {
	"generated": 0, "unloaded": 0, "meshed": 0, "faces": 0,
	"mesh_ms": 0.0, "generation_ms": 0.0, "worst_mesh_ms": 0.0, "attach_ms": 0.0,
	"center": Vector3i.ZERO, "wanted": 0, "queued": 0,
}

## Faces emitted by the most recent rebuild of each coordinate.  Two runs that
## stream the same world must end up with the same map, whatever the frame
## budgets did to the batch boundaries.
var face_counts: Dictionary = {}

var _wanted: Dictionary = {}
var _order: Array[Vector3i] = []
var _queue: Dictionary = {}
var _meshed: Dictionary = {}
var _center := Vector3i(2147483647, 2147483647, 2147483647)
var _active := false
## Dedicated mesh worker: one job at a time, results handed back under a mutex.
var _worker_thread: Thread = null
var _worker_mesher: ChunkMesher = null
var _worker_mutex := Mutex.new()
var _worker_signal := Semaphore.new()
var _worker_stopping := false
var _job_queue: Array = []
var _results: Array = []
var _pending: Dictionary = {}


func setup(target_world: VoxelWorld, chunk_mesher: ChunkMesher) -> void:
	world = target_world
	mesher = chunk_mesher
	_start_worker()
	world.chunk_created.connect(_on_chunk_created)
	world.chunk_removed.connect(_on_chunk_removed)
	_active = true


func _start_worker() -> void:
	if not threaded_meshing or mesher == null or _worker_thread != null:
		return
	_worker_mesher = ChunkMesher.new(mesher.library, mesher.materials)
	_worker_stopping = false
	_worker_thread = Thread.new()
	_worker_thread.start(_worker_loop)


func _exit_tree() -> void:
	# The worker must never outlive the streamer (it reads a snapshot and its own
	# mesher, but ownership has to be explicit for a clean teardown).
	_shutdown_worker()


## Stops the worker and waits for it, so no build is running afterwards.
func _shutdown_worker() -> void:
	if _worker_thread == null:
		return
	_worker_mutex.lock()
	_worker_stopping = true
	_worker_mutex.unlock()
	_worker_signal.post()
	_worker_thread.wait_to_finish()
	_worker_thread = null
	_worker_mesher = null
	_job_queue.clear()
	_results.clear()
	_pending.clear()


func _worker_loop() -> void:
	while true:
		_worker_signal.wait()
		_worker_mutex.lock()
		if _worker_stopping and _job_queue.is_empty():
			_worker_mutex.unlock()
			return
		var job: Variant = _job_queue.pop_front() if not _job_queue.is_empty() else null
		_worker_mutex.unlock()
		if job == null:
			continue
		job["result"] = _worker_mesher.build_geometry(job["input"])
		_worker_mutex.lock()
		_results.append(job)
		_worker_mutex.unlock()


func _ready() -> void:
	if world != null and not _active:
		setup(world, mesher)


# --- public API -----------------------------------------------------------

## Chunk coordinate that contains a world position (floor semantics).
static func chunk_of(world_position: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_position.x / SIZE),
		floori(world_position.y / SIZE),
		floori(world_position.z / SIZE)
	)


## True once every chunk in the wanted set is loaded and meshed.
func is_settled() -> bool:
	if not _active:
		return false
	return _wanted.size() > 0 and _queue.is_empty() and _pending.is_empty() and world.chunks.size() >= _wanted.size()


## True once every chunk within `radius` of the given position has been meshed at
## least once, so the player can safely be placed there (collision exists).
func is_area_ready(world_position: Vector3, radius: int) -> bool:
	if not _active:
		return false
	var center := chunk_of(world_position)
	for offset_y in range(-1, 2):
		for offset_z in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				var coord := center + Vector3i(offset_x, offset_y, offset_z)
				if coord.y < 0 or coord.y >= WorldGen.CHUNKS_Y:
					continue
				if not _meshed.has(coord):
					return false
	return true


func loaded_count() -> int:
	return world.chunks.size() if world != null else 0


## Statistics of the mesher that actually built the geometry.  With threaded
## meshing the builds happen on the worker mesher, so the main mesher's counters
## stay at zero; reports should read this instead.  The main mesher's
## `assemble_ms` (ArrayMesh upload + collision shape) is merged in.
func mesher_stats() -> Dictionary:
	var merged: Dictionary = (_worker_mesher.stats if _worker_mesher != null else mesher.stats).duplicate()
	if mesher != null:
		merged["assemble_ms"] = float(mesher.stats.get("assemble_ms", 0.0))
	return merged


func wanted_count() -> int:
	return _wanted.size()


func queued_count() -> int:
	return _queue.size()


func view_count() -> int:
	return views.size()


## Forces a full rebuild of the wanted set at this position (used on spawn/load).
func focus_at(world_position: Vector3) -> void:
	_center = chunk_of(world_position)
	_rebuild_wanted()
	_unload_out_of_range()
	_scan_dirty()


## Drops every rendered view and every logical chunk.
func clear() -> void:
	_shutdown_worker()
	_start_worker()
	for coord: Vector3i in views.keys():
		_destroy_view(coord)
	for coord: Vector3i in world.chunks.keys():
		world.unload_chunk(coord)
	_queue.clear()
	_wanted.clear()
	_order.clear()
	_meshed.clear()
	face_counts.clear()
	stats["center"] = Vector3i(2147483647, 2147483647, 2147483647)
	_center = stats["center"]


# --- frame loop -----------------------------------------------------------

func _process(_delta: float) -> void:
	if not _active:
		return
	var frame_started := Time.get_ticks_usec()
	var focus: Vector3 = _focus_position()
	var center := chunk_of(focus)
	if center != _center:
		_center = center
		_rebuild_wanted()
		_unload_out_of_range()
	_scan_dirty()
	stats["center"] = _center
	stats["wanted"] = _wanted.size()
	stats["queued"] = _queue.size()
	_generate_batch()
	if threaded_meshing:
		# Collect first so a free worker is available for this frame's submits.
		_collect_mesh_batch()
		_submit_mesh_batch(frame_started)
	else:
		_mesh_batch()


## Overridable hook so the game can stream around the player.
func _focus_position() -> Vector3:
	if focus_node != null and is_instance_valid(focus_node):
		return focus_node.global_position
	return global_position


# --- wanted set -----------------------------------------------------------

func _rebuild_wanted() -> void:
	_wanted.clear()
	_order.clear()
	var lowest_y := maxi(0, _center.y - vertical_radius)
	var highest_y := mini(WorldGen.CHUNKS_Y - 1, _center.y + vertical_radius)
	var radius_squared := render_radius * render_radius
	for chunk_y in range(lowest_y, highest_y + 1):
		for chunk_z in range(_center.z - render_radius, _center.z + render_radius + 1):
			for chunk_x in range(_center.x - render_radius, _center.x + render_radius + 1):
				var dx := chunk_x - _center.x
				var dz := chunk_z - _center.z
				if dx * dx + dz * dz > radius_squared:
					continue
				var coord := Vector3i(chunk_x, chunk_y, chunk_z)
				_wanted[coord] = true
				_order.append(coord)
	_order.sort_custom(_nearer_first)
	for coord: Vector3i in _queue.keys():
		if not _wanted.has(coord):
			_queue.erase(coord)


func _nearer_first(a: Vector3i, b: Vector3i) -> bool:
	var da := (a - _center)
	var db := (b - _center)
	# Prefer the vertical band the player is standing in, then distance.
	var a_distance := float(da.x * da.x + da.y * da.y * 4 + da.z * da.z)
	var b_distance := float(db.x * db.x + db.y * db.y * 4 + db.z * db.z)
	if a_distance == b_distance:
		if a.y == b.y:
			return a.z < b.z
		return a.y < b.y
	return a_distance < b_distance


func _unload_out_of_range() -> void:
	for coord: Vector3i in world.chunks.keys():
		if _wanted.has(coord):
			continue
		_unload(coord)


func _unload(coord: Vector3i) -> void:
	world.unload_chunk(coord)
	_queue.erase(coord)
	stats["unloaded"] = int(stats["unloaded"]) + 1


# --- generation ----------------------------------------------------------

func _generate_batch() -> int:
	var budget := maxi(0, generation_budget)
	if budget == 0:
		return 0
	var started := Time.get_ticks_usec()
	var done := 0
	for coord: Vector3i in _order:
		if done >= budget:
			break
		if world.has_chunk(coord):
			continue
		var chunk_started := Time.get_ticks_usec()
		var chunk := world.ensure_chunk(coord)
		if chunk == null:
			continue
		stats["generation_ms"] = float(stats["generation_ms"]) + float(Time.get_ticks_usec() - chunk_started) / 1000.0
		stats["generated"] = int(stats["generated"]) + 1
		done += 1
		# A single chunk can be several milliseconds of work, so the count budget
		# alone is not enough to protect the frame time.
		if float(Time.get_ticks_usec() - started) / 1000.0 >= generation_millisecond_budget:
			break
	return done


# --- meshing -------------------------------------------------------------

## Queues every loaded chunk whose derived geometry is stale.  This single scan
## covers edits, fluid writes and freshly generated chunks without threading a
## signal through every code path that can dirty a mesh.
func _scan_dirty() -> void:
	for coord: Vector3i in world.chunks:
		var chunk: ChunkData = world.chunks[coord]
		if chunk.mesh_dirty:
			_queue[coord] = true


## A neighbour is "final" when it is loaded, or when it is outside the wanted set
## and therefore will never load during this focus.
func _neighbours_final(coord: Vector3i) -> bool:
	for offset: Vector3i in FACE_OFFSETS:
		var neighbour := coord + offset
		if world.has_chunk(neighbour):
			continue
		if _wanted.has(neighbour):
			return false
	return true


func _mesh_batch() -> int:
	# Synchronous path: unit tests and `threaded_meshing = false` call this
	# directly so a single `_process` step meshes in place.
	if _queue.is_empty():
		return 0
	var candidates: Array = _queue.keys()
	candidates.sort_custom(_nearer_first)
	if mesher == null:
		return 0
	var started := Time.get_ticks_usec()
	var done := 0
	for coord: Vector3i in candidates:
		if done >= maxi(0, mesh_budget):
			break
		if not world.has_chunk(coord):
			_queue.erase(coord)
			continue
		if not _neighbours_final(coord):
			continue
		rebuild(coord)
		_queue.erase(coord)
		done += 1
		if float(Time.get_ticks_usec() - started) / 1000.0 >= mesh_millisecond_budget:
			break
	return done


## Rebuilds one chunk's render + collision geometry synchronously.
func rebuild(coord: Vector3i) -> void:
	var chunk: ChunkData = world.get_chunk(coord)
	if chunk == null:
		return
	_apply_result(coord, mesher.build_geometry(mesher.capture_input(chunk, world)), chunk.mesh_revision)


# --- threaded meshing -----------------------------------------------------
#
# ChunkMesher.build_input is several milliseconds of GDScript per chunk.  Running
# it inside the frame was the reported frame-time spike, so the main thread only
# captures an immutable input snapshot per candidate and submits it to a worker
# thread; finished meshes are attached when they complete.  The submission is
# still frame-budgeted (`mesh_budget`, `mesh_millisecond_budget`) and bounded by
# `max_mesh_in_flight`, and every worker owns its own ChunkMesher so concurrent
# builds never share scratch buffers.

## Submits queued chunks whose neighbours are final to the worker queue.
func _submit_mesh_batch(frame_started: int) -> void:
	if _queue.is_empty() or _worker_thread == null:
		return
	if _pending.size() >= maxi(1, max_mesh_in_flight):
		return
	var candidates: Array = _queue.keys()
	candidates.sort_custom(_nearer_first)
	var submitted := 0
	for coord: Vector3i in candidates:
		if submitted >= maxi(0, mesh_budget):
			break
		if _pending.size() >= maxi(1, max_mesh_in_flight):
			break
		if not world.has_chunk(coord):
			_queue.erase(coord)
			continue
		if not _neighbours_final(coord):
			continue
		# A coord with a build already in flight must not be submitted twice: the
		# dirty scan re-adds it every frame until its result is attached.
		if _pending.has(coord):
			continue
		var chunk: ChunkData = world.get_chunk(coord)
		var input := _worker_mesher.capture_input(chunk, world)
		_worker_mutex.lock()
		_job_queue.append({"coord": coord, "input": input, "result": {}, "revision": chunk.mesh_revision})
		_worker_mutex.unlock()
		_worker_signal.post()
		_pending[coord] = true
		_queue.erase(coord)
		submitted += 1
		if float(Time.get_ticks_usec() - frame_started) / 1000.0 >= mesh_millisecond_budget:
			break


## Attaches every finished worker mesh.  Main thread only (touches the scene).
func _collect_mesh_batch() -> int:
	if _results.is_empty():
		return 0
	_worker_mutex.lock()
	var finished: Array = _results
	_results = []
	_worker_mutex.unlock()
	for job: Dictionary in finished:
		var coord: Vector3i = job["coord"]
		_pending.erase(coord)
		if not world.has_chunk(coord):
			_queue.erase(coord)
			continue
		_apply_result(coord, job["result"], int(job.get("revision", -1)))
		# Keep the coordinate queued when the build turned out to be stale (a
		# newer edit, or a change to its neighbour set, landed while it was in
		# flight).  The dirty scan already re-added it this frame, so leaving it
		# queued lets the submit pass below rebuild it immediately.
		var chunk: ChunkData = world.get_chunk(coord)
		if chunk == null or not chunk.mesh_dirty:
			_queue.erase(coord)
	return finished.size()


## Builds the view nodes for a finished geometry and records its statistics.
## `revision` is the chunk's dirty revision captured at submit time: the mesh
## stays dirty when a newer edit landed while the worker was building, so the
## edit is not lost.
func _apply_result(coord: Vector3i, geometry: Dictionary, revision: int = -1) -> void:
	var attach_started := Time.get_ticks_usec()
	# The worker produced plain arrays; turn them into meshes here, on the main
	# thread (engine resource creation).
	var result: Dictionary = mesher.assemble(geometry)
	var view := _ensure_view(coord)
	_clear_view(view)
	var mesh_ms := float(result.get("ms", 0.0))
	stats["mesh_ms"] = float(stats["mesh_ms"]) + mesh_ms
	stats["worst_mesh_ms"] = maxf(float(stats["worst_mesh_ms"]), mesh_ms)
	stats["faces"] = int(stats["faces"]) + int(result.get("faces", 0))
	stats["meshed"] = int(stats["meshed"]) + 1

	var solid: ArrayMesh = result.get("mesh", null)
	if solid != null:
		var instance := MeshInstance3D.new()
		instance.name = "Solid"
		instance.mesh = solid
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		view.add_child(instance)
	var water: ArrayMesh = result.get("water_mesh", null)
	if water != null:
		var water_instance := MeshInstance3D.new()
		water_instance.name = "Water"
		water_instance.mesh = water
		# Water must never cast a shadow: it is a translucent surface and a
		# shadow volume would darken the riverbed under it.
		water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.add_child(water_instance)
	if collision_enabled:
		var collision: ArrayMesh = result.get("collision", null)
		if collision != null:
			var body := StaticBody3D.new()
			body.name = "Collision"
			var shape := CollisionShape3D.new()
			shape.shape = collision.create_trimesh_shape()
			body.add_child(shape)
			view.add_child(body)
	var chunk: ChunkData = world.get_chunk(coord)
	if chunk != null:
		# Only clear the dirty flag when no edit happened while the mesh was being
		# built; otherwise the chunk must be submitted again.
		if revision < 0 or chunk.mesh_revision <= revision:
			chunk.mesh_dirty = false
			chunk.collision_dirty = false
	_meshed[coord] = true
	face_counts[coord] = int(result.get("faces", 0))
	stats["attach_ms"] = float(stats["attach_ms"]) + float(Time.get_ticks_usec() - attach_started) / 1000.0


# --- views ---------------------------------------------------------------

func _ensure_view(coord: Vector3i) -> Node3D:
	var existing: Variant = views.get(coord)
	if existing != null:
		return existing
	var view := Node3D.new()
	view.name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
	view.position = Vector3(VoxelWorld.chunk_origin(coord))
	views[coord] = view
	add_child(view)
	return view


func _clear_view(view: Node3D) -> void:
	for child in view.get_children():
		view.remove_child(child)
		child.queue_free()


func _destroy_view(coord: Vector3i) -> void:
	var view: Variant = views.get(coord)
	if view == null:
		return
	views.erase(coord)
	var node := view as Node3D
	node.visible = false
	if node.get_parent() == self:
		remove_child(node)
	node.queue_free()


# --- signal handlers -----------------------------------------------------

func _on_chunk_created(coord: Vector3i) -> void:
	_queue[coord] = true
	# The new chunk changes the border every loaded neighbour culls against, so
	# their meshes are stale too.  `mark_dirty()` (not just a queue entry) also
	# bumps their revision, which discards any build already in flight for them:
	# a build snapshotted before this chunk loaded would otherwise attach with
	# the old border and clear the dirty flag.
	for offset: Vector3i in FACE_OFFSETS:
		var neighbour: ChunkData = world.chunks.get(coord + offset, null)
		if neighbour != null:
			neighbour.mark_dirty()
			_queue[coord + offset] = true


func _on_chunk_removed(coord: Vector3i) -> void:
	_destroy_view(coord)
	_queue.erase(coord)
	_meshed.erase(coord)
	# Symmetric to creation: the removed chunk's border disappears, so every
	# loaded neighbour must be rebuilt, and an in-flight build that still culled
	# against the removed chunk has to be discarded.
	for offset: Vector3i in FACE_OFFSETS:
		var neighbour: ChunkData = world.chunks.get(coord + offset, null)
		if neighbour != null:
			neighbour.mark_dirty()
			_queue[coord + offset] = true


# --- diagnostics ---------------------------------------------------------

func report() -> Dictionary:
	var loaded := loaded_count()
	return {
		"render_radius": render_radius,
		"vertical_radius": vertical_radius,
		"center": _center,
		"wanted": _wanted.size(),
		"loaded": loaded,
		"queued": _queue.size(),
		"views": views.size(),
		"generated": int(stats["generated"]),
		"unloaded": int(stats["unloaded"]),
		"meshed": int(stats["meshed"]),
		"faces": int(stats["faces"]),
		"faces_hash": faces_fingerprint(),
		"mesh_ms_total": float(stats["mesh_ms"]),
		"attach_ms_total": float(stats["attach_ms"]),
		"meshes_in_flight": _pending.size(),
		"worst_mesh_ms": float(stats["worst_mesh_ms"]),
		"generation_ms_total": float(stats["generation_ms"]),
	}


## Stable hash of the geometry currently streamed in: coordinate + face count of
## every chunk's most recent build.  A non-deterministic streamer shows up here
## as two different values for two identical runs.
func faces_fingerprint() -> int:
	var hash_value := 0
	for coord: Vector3i in VoxelWorld.sorted_coords(face_counts):
		hash_value = VoxelWorld._mix(hash_value, coord.x, coord.y, coord.z)
		hash_value = (hash_value * 1000003 + int(face_counts[coord])) & 0x7FFFFFFFFFFFFFFF
	return hash_value
