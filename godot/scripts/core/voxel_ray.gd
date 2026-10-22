class_name VoxelRay
extends RefCounted

const BlockShape = preload("res://scripts/core/block_shape.gd")

## Amanatides & Woo voxel traversal.
##
## Walks the grid one cell at a time and reports the first cell whose block
## satisfies the caller, plus the face normal it entered through.  Exact and
## independent of physics colliders, so block targeting keeps working while
## collision meshes are being rebuilt.

const EPSILON := 1e-9


static func cast(world: VoxelWorld, origin: Vector3, direction: Vector3, max_distance: float, include_liquids: bool = false) -> Dictionary:
	var dir := direction.normalized()
	if dir.length_squared() < 0.5:
		return {"hit": false}
	# Traverse half-cell coordinates.  Full cubes occupy both halves, while a
	# shaped block can leave one half empty and expose its internal stair riser.
	var position := Vector3i(floori(origin.x * 2.0), floori(origin.y * 2.0), floori(origin.z * 2.0))
	var step := Vector3i(0, 0, 0)
	var t_delta := Vector3(INF, INF, INF)
	var t_max := Vector3(INF, INF, INF)
	for axis in 3:
		var component := dir[axis]
		if absf(component) < EPSILON:
			continue
		if component > 0.0:
			step[axis] = 1
			t_delta[axis] = 0.5 / component
			t_max[axis] = (float(position[axis] + 1) * 0.5 - origin[axis]) / component
		else:
			step[axis] = -1
			t_delta[axis] = -0.5 / component
			t_max[axis] = (float(position[axis]) * 0.5 - origin[axis]) / component
	var travelled := 0.0
	var normal := Vector3i.ZERO
	var guard := 0
	while travelled <= max_distance and guard < 512:
		guard += 1
		var cell := Vector3i(floori(float(position.x) * 0.5), floori(float(position.y) * 0.5),
			floori(float(position.z) * 0.5))
		var half_cell := Vector3i(posmod(position.x, 2), posmod(position.y, 2), posmod(position.z, 2))
		var block_id := world.get_block(cell)
		var occupied := _matches(block_id, include_liquids)
		if occupied and BlockShape.is_shaped(block_id):
			occupied = BlockShape.is_occupied(block_id, world.get_orientation(cell), half_cell)
		if occupied:
			return {
				"hit": true,
				"block": cell,
				"normal": normal,
				"distance": travelled,
				"block_id": block_id,
			}
		# Advance along the axis with the nearest boundary crossing.
		var axis_index := 0
		if t_max.y < t_max.x:
			axis_index = 1
		if t_max.z < t_max[axis_index]:
			axis_index = 2
		travelled = t_max[axis_index]
		if travelled > max_distance:
			break
		var axis_step := Vector3i.ZERO
		axis_step[axis_index] = step[axis_index]
		normal = -axis_step
		position += axis_step
		t_max[axis_index] += t_delta[axis_index]
	return {"hit": false}


static func _matches(block_id: int, include_liquids: bool) -> bool:
	if block_id == BlockDB.AIR:
		return false
	if BlockDB.is_liquid(block_id):
		return include_liquids
	return true


static func ray_description(hit: Dictionary) -> String:
	if not hit.get("hit", false):
		return "no target"
	var position: Vector3i = hit["block"]
	return "%s at (%d, %d, %d)" % [BlockDB.name_of(int(hit["block_id"])), position.x, position.y, position.z]
