extends RefCounted

const BlockShape = preload("res://scripts/core/block_shape.gd")

## Pure stair occupancy, orientation, boundary and exposed-face contracts.


func name() -> String:
	return "block shape geometry"


func run(h: TestHarness) -> void:
	h.eq(BlockDB.STAIR, 88, "the stair uses the first appended block id")
	h.eq(BlockShape.mask_for(BlockDB.STAIR, 0), 0x3F, "canonical stair is a full lower layer with a rear upper half")
	h.eq(BlockShape.boundary_mask(BlockDB.STAIR, 0, BlockDB.FACE_NY), 0xF, "the canonical stair covers its full bottom boundary")
	h.eq(BlockShape.boundary_mask(BlockDB.STAIR, 0, BlockDB.FACE_PY), 0x3, "the canonical stair covers half its top boundary")
	h.eq(BlockShape.boundary_mask(BlockDB.STAIR, 0, BlockDB.FACE_PZ), 0x3, "the low front boundary has half-height coverage")
	h.eq(BlockShape.boundary_mask(BlockDB.STAIR, 0, BlockDB.FACE_NZ), 0xF, "the raised rear boundary is full height")
	h.eq(BlockShape.exposed_faces(BlockDB.STAIR, 0).size(), 22, "the canonical stair has twenty-two exposed half-cell faces")

	# Facing order is +Z, +X, -Z, -X; the upper half is always opposite it.
	var expected_upper_half := [
		Vector3i(0, 1, 0), Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 0),
	]
	for orientation in 4:
		var mask := BlockShape.mask_for(BlockDB.STAIR, orientation)
		h.eq(mask, BlockShape.mask_for(BlockDB.STAIR, orientation), "orientation %d mask is deterministic" % orientation)
		h.check(BlockShape.is_occupied(BlockDB.STAIR, orientation, expected_upper_half[orientation]),
			"orientation %d places the raised half opposite its facing" % orientation)
		h.eq(BlockShape.exposed_faces(BlockDB.STAIR, orientation).size(), 22,
			"orientation %d preserves the exposed face count" % orientation)
		h.eq(_bit_count(mask), 6, "orientation %d occupies six half-cells" % orientation)
		var flipped_cell: Vector3i = expected_upper_half[orientation]
		flipped_cell.y = 0
		h.check(BlockShape.is_occupied(BlockDB.STAIR, orientation + 4, flipped_cell),
			"orientation %d flips the raised half to the bottom" % orientation)
		h.eq(_bit_count(BlockShape.mask_for(BlockDB.STAIR, orientation + 4)), 6,
			"upside-down orientation %d preserves occupancy" % orientation)

	h.check(not BlockShape.is_valid_orientation(-1), "negative orientations are invalid")
	h.check(not BlockShape.is_valid_orientation(8), "orientations above seven are invalid")
	h.eq(BlockShape.mask_for(BlockDB.STAIR, 8), 0, "invalid orientation has no occupancy")
	h.eq(BlockShape.mask_for(BlockDB.STONE, 0), 0xFF, "full cubes occupy all half-cells")
	h.eq(BlockShape.mask_for(BlockDB.AIR, 0), 0, "air occupies no half-cells")
	h.eq(BlockShape.orientation_for_placement(Vector3(0, 0, 1), Vector3i.UP), 0, "+Z look selects facing 0")
	h.eq(BlockShape.orientation_for_placement(Vector3(1, 0, 0), Vector3i.UP), 1, "+X look selects facing 1")
	h.eq(BlockShape.orientation_for_placement(Vector3(0, 0, -1), Vector3i.UP), 2, "-Z look selects facing 2")
	h.eq(BlockShape.orientation_for_placement(Vector3(-1, 0, 0), Vector3i.DOWN), 7, "-X look on a ceiling selects upside-down facing 3")
	h.finish()


func _bit_count(mask: int) -> int:
	var count := 0
	for bit in 8:
		if (mask & (1 << bit)) != 0:
			count += 1
	return count
