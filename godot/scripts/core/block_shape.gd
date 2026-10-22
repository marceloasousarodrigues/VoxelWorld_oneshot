class_name BlockShape
extends RefCounted

## Small, pure geometry description for the first partial block family.
##
## Cells are represented by eight half-block occupancy bits.  The full-cube
## mesher remains on its existing path; this helper is queried only when a
## shaped block meets another shaped block or exposes partial geometry.

const RESOLUTION := 2
const HALF_CELLS := 8

const FACE_PX := BlockDB.FACE_PX
const FACE_NX := BlockDB.FACE_NX
const FACE_PY := BlockDB.FACE_PY
const FACE_NY := BlockDB.FACE_NY
const FACE_PZ := BlockDB.FACE_PZ
const FACE_NZ := BlockDB.FACE_NZ

const FACE_STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func is_valid_orientation(orientation: int) -> bool:
	return orientation >= 0 and orientation <= 7


## Facing values use +Z, +X, -Z, -X order.  Ties keep the first direction.
static func orientation_for_placement(horizontal_forward: Vector3, hit_normal: Vector3i) -> int:
	var direction := Vector3(horizontal_forward.x, 0.0, horizontal_forward.z).normalized()
	var facings: Array[Vector3] = [Vector3(0.0, 0.0, 1.0), Vector3.RIGHT,
		Vector3(0.0, 0.0, -1.0), Vector3.LEFT]
	var facing := 0
	var best_dot := -INF
	for index in facings.size():
		var score := direction.dot(facings[index])
		if score > best_dot:
			best_dot = score
			facing = index
	return facing + (4 if hit_normal == Vector3i.DOWN else 0)


static func is_shaped(block_id: int) -> bool:
	return block_id == BlockDB.STAIR or block_id == BlockDB.SLATE_STAIR \
		or block_id == BlockDB.SLATE_SLAB


## True for the half-height slab family (bottom at orientation 0, top at 4).
static func is_slab(block_id: int) -> bool:
	return block_id == BlockDB.SLATE_SLAB


## Orientation values: 0=+Z, 1=+X, 2=-Z, 3=-X; add four for upside-down.
## The canonical +Z stair has a full lower layer and an upper layer toward -Z.
static func mask_for(block_id: int, orientation: int) -> int:
	if not is_valid_orientation(orientation):
		return 0
	if not is_shaped(block_id):
		return 0xFF if BlockDB.is_solid(block_id) else 0
	if is_slab(block_id):
		# A slab has only two meaningful states: the bottom or the top half.
		return 0x0F if orientation < 4 else 0xF0
	var result := 0
	for y in RESOLUTION:
		for z in RESOLUTION:
			for x in RESOLUTION:
				# Canonical: bottom layer is full; top layer occupies z == 0.
				var occupied := y == 0 or z == 0
				if not occupied:
					continue
				var rx := x
				var rz := z
				match orientation % 4:
					1:
						rx = z
						rz = 1 - x
					2:
						rx = 1 - x
						rz = 1 - z
					3:
						rx = 1 - z
						rz = x
				var ry := 1 - y if orientation >= 4 else y
				result |= 1 << _bit(rx, ry, rz)
	return result


static func is_occupied(block_id: int, orientation: int, half_cell: Vector3i) -> bool:
	if half_cell.x < 0 or half_cell.x >= 2 or half_cell.y < 0 or half_cell.y >= 2 \
			or half_cell.z < 0 or half_cell.z >= 2:
		return false
	return (mask_for(block_id, orientation) & (1 << _bit(half_cell.x, half_cell.y, half_cell.z))) != 0


## Four bit positions are ordered by the two increasing local axes of the face:
## PX/NX: y,z; PY/NY: x,z; PZ/NZ: x,y.
static func boundary_mask(block_id: int, orientation: int, face: int) -> int:
	var result := 0
	for second in 2:
		for first in 2:
			var cell := Vector3i.ZERO
			match face:
				FACE_PX, FACE_NX:
					cell = Vector3i(1 if face == FACE_PX else 0, first, second)
				FACE_PY, FACE_NY:
					cell = Vector3i(first, 1 if face == FACE_PY else 0, second)
				FACE_PZ, FACE_NZ:
					cell = Vector3i(first, second, 1 if face == FACE_PZ else 0)
				_:
					return 0
			if is_occupied(block_id, orientation, cell):
				result |= 1 << (first + 2 * second)
	return result


## Enumerates all exterior half-cell faces in deterministic cell/face order.
## Each row is {"cell": Vector3i, "face": int}; adjacent occupied half-cells
## within this block have already had their shared face removed.
static func exposed_faces(block_id: int, orientation: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for y in RESOLUTION:
		for z in RESOLUTION:
			for x in RESOLUTION:
				var cell := Vector3i(x, y, z)
				if not is_occupied(block_id, orientation, cell):
					continue
				for face in 6:
					var neighbour := cell + FACE_STEPS[face]
					if is_occupied(block_id, orientation, neighbour):
						continue
					result.append({"cell": cell, "face": face})
	return result


static func _bit(x: int, y: int, z: int) -> int:
	return x + 2 * (z + 2 * y)
