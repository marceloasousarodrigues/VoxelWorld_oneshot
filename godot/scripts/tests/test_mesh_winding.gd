extends RefCounted

## Face winding.
##
## Godot's front faces are wound so that the right-hand-rule normal of the
## triangle points *into* the solid (the engine's own `BoxMesh` demonstrates
## this).  The mesher emitted the opposite winding, so every face was a back
## face: `cull_back` materials vanished from the outside (the streaked terrain)
## and, worse, the collision trimesh reported inverted normals so a
## `CharacterBody3D` never registered the ground as a floor and fell through it.
##
## This module pins the convention to `BoxMesh` and then checks every face the
## mesher emits -- render and collision -- against that convention.


func name() -> String:
	return "mesh winding"


func _triangle_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a)


## The sign of the right-hand-rule normal of an outward-facing triangle,
## according to Godot itself.  -1 means "points inward", which is the front-face
## convention this project must match.
func _reference_sign(h: TestHarness) -> int:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var faces: PackedVector3Array = box.get_faces()
	var sign_value := 0
	var index := 0
	while index + 2 < faces.size():
		var a := faces[index]
		var b := faces[index + 1]
		var c := faces[index + 2]
		if absf(a.y - 0.5) < 0.001 and absf(b.y - 0.5) < 0.001 and absf(c.y - 0.5) < 0.001:
			sign_value = signi(int(signf(_triangle_normal(a, b, c).y)))
		index += 3
	return sign_value


func run(h: TestHarness) -> void:
	# 1) The engine reference: an outward +Y face winds inward.
	h.eq(_reference_sign(h), -1, "Godot's own BoxMesh winds outward faces inward (reference)")

	# 2) Every cube face the mesher emits must follow the same convention, so the
	#    cross-product normal is opposite the outward face normal.
	var wrong := 0
	for face in 6:
		var corners: Array = ChunkMesher.FACE_CORNERS[face]
		var order: Array = ChunkMesher.QUAD_INDICES
		var a: Vector3 = corners[int(order[0])]
		var b: Vector3 = corners[int(order[1])]
		var c: Vector3 = corners[int(order[2])]
		var outward: Vector3 = ChunkMesher.FACE_NORMALS[face]
		if _triangle_normal(a, b, c).dot(outward) >= 0.0:
			wrong += 1
	h.eq(wrong, 0, "all six cube faces wind outward, matching Godot's convention")

	# 3) End to end through `build()`: every triangle of the culled solid mesh has
	#    a geometric normal opposed to the stored outward vertex normal.  This is
	#    what `cull_back` and the collision trimesh actually consume.
	var library := TextureLibrary.new()
	library.load_all()
	var mesher := ChunkMesher.new(library, VoxelMaterials.new(library))
	var world := VoxelWorld.new(17017)
	var chunk := ChunkData.new(Vector3i.ZERO)
	chunk.generated = true
	world.adopt_chunk(chunk)
	chunk.blocks[ChunkData.cell_index(8, 8, 8)] = BlockDB.STONE
	chunk.blocks[ChunkData.cell_index(9, 8, 8)] = BlockDB.STONE
	var result := mesher.build(chunk, world)

	var mesh: ArrayMesh = result["mesh"]
	h.check(mesh != null, "the solid mesh exists")
	var bad_triangles := 0
	var checked := 0
	for surface_index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var i := 0
		while i + 2 < indices.size():
			var ia := int(indices[i])
			var ib := int(indices[i + 1])
			var ic := int(indices[i + 2])
			var geometric := _triangle_normal(vertices[ia], vertices[ib], vertices[ic])
			var outward := normals[ia] + normals[ib] + normals[ic]
			if geometric.dot(outward) >= 0.0:
				bad_triangles += 1
			checked += 1
			i += 3
	h.greater(float(checked), 0.0, "the solid mesh has triangles to check")
	h.eq(bad_triangles, 0, "every solid-mesh triangle winds outward like Godot (%d checked)" % checked)

	# 4) The collision trimesh must share the render winding, because a
	#    `ConcavePolygonShape3D` derives its surface normal from the winding and
	#    `backface_collision` is off.  For an isolated block every face points away
	#    from the block centre, so the normal must point back toward it.
	var collision: ArrayMesh = result["collision"]
	h.check(collision != null, "the collision mesh exists")
	var centre := Vector3(8.5, 8.5, 8.5)
	var bad_collision := 0
	var collision_triangles := 0
	for surface_index in collision.get_surface_count():
		var arrays: Array = collision.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var i := 0
		while i + 2 < indices.size():
			var ia := int(indices[i])
			var ib := int(indices[i + 1])
			var ic := int(indices[i + 2])
			var tri_centre := (vertices[ia] + vertices[ib] + vertices[ic]) / 3.0
			var geometric := _triangle_normal(vertices[ia], vertices[ib], vertices[ic])
			if geometric.dot(tri_centre - centre) >= 0.0:
				bad_collision += 1
			collision_triangles += 1
			i += 3
	h.greater(float(collision_triangles), 0.0, "the collision mesh has triangles to check")
	h.eq(bad_collision, 0, "every collision triangle winds like the render mesh (%d checked)" % collision_triangles)

	h.finish()
