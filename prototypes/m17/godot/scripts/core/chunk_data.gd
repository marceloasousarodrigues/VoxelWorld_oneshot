class_name ChunkData
extends RefCounted

## Authoritative logical voxel data for one 16x16x16 chunk.
##
## Cell order matches the shared M17 fixture contract: `x + 16 * (z + 16 * y)`.
## Rendered meshes are derived data and are never stored here.

const SIZE := 16
const CELLS := SIZE * SIZE * SIZE
const COLUMNS := SIZE * SIZE

const NO_FLUID := 0
const SOURCE_LEVEL := 8

var coord: Vector3i
var blocks: PackedByteArray
var fluid: PackedByteArray
var sources: PackedByteArray
var biomes: PackedByteArray
var surface: PackedInt32Array
var generated := false
var edited := false
var solid_cells := 0

# Derived state.
var mesh_dirty := true
var collision_dirty := true
## Bumped on every `mark_dirty()`.  The streamer records it when it snapshots a
## chunk and only clears `mesh_dirty` when no newer edit happened while the mesh
## was being built off the main thread.
var mesh_revision := 0


func _init(chunk_coord: Vector3i = Vector3i.ZERO) -> void:
	coord = chunk_coord
	blocks = PackedByteArray()
	blocks.resize(CELLS)
	fluid = PackedByteArray()
	fluid.resize(CELLS)
	sources = PackedByteArray()
	sources.resize(CELLS)
	biomes = PackedByteArray()
	biomes.resize(COLUMNS)
	surface = PackedInt32Array()
	surface.resize(COLUMNS)


static func cell_index(local_x: int, local_y: int, local_z: int) -> int:
	return local_x + SIZE * (local_z + SIZE * local_y)


static func column_index(local_x: int, local_z: int) -> int:
	return local_x + SIZE * local_z


static func index_to_local(index: int) -> Vector3i:
	return Vector3i(index % SIZE, index / (SIZE * SIZE), (index / SIZE) % SIZE)


func get_block(local_x: int, local_y: int, local_z: int) -> int:
	return blocks[cell_index(local_x, local_y, local_z)]


func set_block(local_x: int, local_y: int, local_z: int, block_id: int) -> void:
	blocks[cell_index(local_x, local_y, local_z)] = block_id


func fluid_at(index: int) -> int:
	return fluid[index]


func is_source(index: int) -> bool:
	return sources[index] == 1


## Marks the chunk (and its derived state) as needing a mesh rebuild.
func mark_dirty() -> void:
	mesh_dirty = true
	collision_dirty = true
	mesh_revision += 1


func highest_solid_at(local_x: int, local_z: int) -> int:
	var top := -1
	for y in range(SIZE - 1, -1, -1):
		if BlockDB.is_solid(blocks[cell_index(local_x, y, local_z)]):
			top = y
			break
	return top
