class_name MedievalKit
extends RefCounted

## Reusable M29 medieval roof kit.
##
## `build_gable_roof` writes a believable gable roof from the slate palette:
## a thin eave overhang, two continuous 45-degree ramp planes that rise to a
## triangular ridge cap, timber-framed gable infill, optional finials and an
## optional stone chimney.
## Every cell goes through the ordinary `world.set_block` / `set_block_state`
## path, so the result is editable, mineable and persistent like player work.
##
## `anchor` is the footprint centre at the building's base level; `eave` is the
## first roof row relative to it (the wall top is `eave - 1`).


## Returns a small report: pieces, slabs, ramps, ridges, gable, finials,
## chimney.
static func build_gable_roof(world: VoxelWorld, anchor: Vector3i, hx: int, hz: int,
		eave: int, options: Dictionary = {}) -> Dictionary:
	var report := {"pieces": 0, "slabs": 0, "ramps": 0, "ridges": 0, "gable": 0,
		"finials": 0, "chimney": 0}
	var post: int = int(options.get("gable_post", BlockDB.DARK_TIMBER))
	var brace: int = int(options.get("gable_brace", BlockDB.TIMBER_BRACE))
	var infill: int = int(options.get("gable_infill", BlockDB.PLASTER))

	# Thin eaves overhang one block past both long walls and both gable ends.
	# They sit at wall-top level as upper-half slabs, so their top is flush with
	# the ramp's low edge.
	for side in [-1, 1]:
		for x in range(-hx - 1, hx + 2):
			report["pieces"] += _put_state(world, anchor + Vector3i(x, eave - 1, side * (hz + 1)),
				BlockDB.SLATE_SLAB, 4)
			report["slabs"] += 1

	# Continuous 45-degree ramp planes.  Orientation 0 rises toward -Z,
	# orientation 2 toward +Z, so neighbouring rows share one flat roof plane.
	for step in hz:
		for side in [-1, 1]:
			var orientation := 0 if side > 0 else 2
			var z: int = side * (hz - step)
			for x in range(-hx, hx + 1):
				report["pieces"] += _put_state(world, anchor + Vector3i(x, eave + step, z),
					BlockDB.SLATE_RAMP, orientation)
				report["ramps"] += 1

	# Triangular ridge cap, long axis along X, sitting on the two ramp apexes.
	for x in range(-hx, hx + 1):
		report["pieces"] += _put_state(world, anchor + Vector3i(x, eave + hz, 0),
			BlockDB.SLATE_RIDGE, 0)
		report["ridges"] += 1

	if bool(options.get("gable", true)):
		for side in [-1, 1]:
			var gx: int = side * hx
			var placed_gable := 0
			for y in range(eave, eave + hz):
				var width := hz - (y - eave)
				for z in range(-width, width + 1):
					var position := anchor + Vector3i(gx, y, z)
					if _block_at(world, position) != BlockDB.AIR:
						continue
					var block_id := infill
					if absi(z) == width:
						block_id = post
					elif absi(z) == width - 1 and width >= 2:
						block_id = brace
					placed_gable += _put(world, position, block_id)
			report["pieces"] += placed_gable
			report["gable"] += placed_gable

	if bool(options.get("finials", false)):
		for x in [-hx, hx]:
			report["pieces"] += _put_state(world, anchor + Vector3i(x, eave + hz + 1, 0),
				BlockDB.FINIAL, 0)
			report["finials"] += 1

	var chimney: Variant = options.get("chimney")
	if chimney != null and chimney is Dictionary:
		var cx := int((chimney as Dictionary).get("x", 0))
		var cz := int((chimney as Dictionary).get("z", 0))
		var top := int((chimney as Dictionary).get("top", eave + hz + 2))
		for y in range(1, top + 1):
			report["pieces"] += _put(world, anchor + Vector3i(cx, y, cz), BlockDB.CHIMNEY)
			report["chimney"] += 1

	return report


static func _block_at(world: VoxelWorld, position: Vector3i) -> int:
	if not world.in_world_vertical(position.y):
		return BlockDB.AIR
	var coord := VoxelWorld.world_to_chunk(position)
	if not world.has_chunk(coord):
		world.ensure_chunk(coord)
	return world.get_block(position)


static func _put(world: VoxelWorld, position: Vector3i, block_id: int) -> int:
	if not world.in_world_vertical(position.y):
		return 0
	var coord := VoxelWorld.world_to_chunk(position)
	if not world.has_chunk(coord):
		world.ensure_chunk(coord)
	if world.get_block(position) == block_id:
		return 0
	return 1 if world.set_block(position, block_id, true) else 0


static func _put_state(world: VoxelWorld, position: Vector3i, block_id: int,
		orientation: int) -> int:
	if not world.in_world_vertical(position.y):
		return 0
	var coord := VoxelWorld.world_to_chunk(position)
	if not world.has_chunk(coord):
		world.ensure_chunk(coord)
	if world.get_block(position) == block_id and world.get_orientation(position) == orientation:
		return 0
	return 1 if world.set_block_state(position, block_id, orientation, true) else 0
