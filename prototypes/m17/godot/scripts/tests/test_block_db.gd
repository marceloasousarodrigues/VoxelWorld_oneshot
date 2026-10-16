extends RefCounted

## Block definition table integrity and the face-culling rules.


func name() -> String:
	return "block definitions"


func run(h: TestHarness) -> void:
	h.eq(BlockDB.AIR, 0, "shared palette keeps AIR at 0")
	h.eq(BlockDB.GRASS, 1, "shared palette keeps GRASS at 1")
	h.eq(BlockDB.DIRT, 2, "shared palette keeps DIRT at 2")
	h.eq(BlockDB.STONE, 3, "shared palette keeps STONE at 3")
	h.eq(BlockDB.WATER, 4, "shared palette keeps WATER at 4")
	h.eq(BlockDB.names.size(), BlockDB.COUNT, "every block id has a name")
	h.eq(BlockDB.face_keys.size(), BlockDB.COUNT, "every block id has face textures")

	h.check(BlockDB.is_solid(BlockDB.STONE), "stone is solid")
	h.check(not BlockDB.is_solid(BlockDB.WATER), "water is not solid")
	h.check(not BlockDB.is_solid(BlockDB.AIR), "air is not solid")
	h.check(not BlockDB.is_solid(BlockDB.GRASS_TUFT), "decoration does not block movement")
	h.check(BlockDB.is_liquid(BlockDB.WATER), "water is a liquid")
	h.check(BlockDB.is_opaque(BlockDB.GRASS), "grass is opaque")
	h.check(not BlockDB.is_opaque(BlockDB.GLASS), "glass is not opaque")
	h.check(not BlockDB.is_opaque(BlockDB.OAK_LEAVES), "leaves are not opaque")
	h.check(not BlockDB.is_breakable(BlockDB.BEDROCK), "bedrock is unbreakable")
	h.check(not BlockDB.is_breakable(BlockDB.WATER), "water cannot be broken directly")
	h.check(BlockDB.is_breakable(BlockDB.STONE), "stone is breakable")

	h.eq(BlockDB.drop_of(BlockDB.STONE), BlockDB.COBBLESTONE, "stone drops cobblestone")
	h.eq(BlockDB.drop_of(BlockDB.GRASS), BlockDB.DIRT, "grass drops dirt")
	h.eq(BlockDB.drop_of(BlockDB.BEDROCK), BlockDB.NO_DROP, "bedrock drops nothing")

	# Face culling: a face is skipped only when the neighbour really hides it.
	h.check(BlockDB.hides_neighbour_face(BlockDB.STONE, BlockDB.STONE), "stone hides the face against stone")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.STONE, BlockDB.AIR), "stone face is visible against air")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.STONE, BlockDB.WATER), "stone face is visible against water")
	h.check(BlockDB.hides_neighbour_face(BlockDB.WATER, BlockDB.WATER), "water hides the face against water")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.WATER, BlockDB.AIR), "water surface is visible against air")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.WATER, BlockDB.STONE), "water face against stone is hidden by the stone instead")
	h.check(BlockDB.hides_neighbour_face(BlockDB.GLASS, BlockDB.GLASS), "glass culls its equal neighbours")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.GLASS, BlockDB.AIR), "glass face is visible against air")
	h.check(BlockDB.hides_neighbour_face(BlockDB.OAK_LEAVES, BlockDB.OAK_LEAVES), "canopy interior faces are culled")
	h.check(BlockDB.hides_neighbour_face(BlockDB.OAK_LEAVES, BlockDB.STONE), "opaque neighbours hide leaves faces")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.GRASS, BlockDB.OAK_LEAVES), "grass face stays visible next to leaves")

	# Render layer assignment drives which mesh surface a block lands in.
	h.eq(BlockDB.layer_of(BlockDB.WATER), BlockDB.LAYER_WATER, "water renders in the water layer")
	h.eq(BlockDB.layer_of(BlockDB.GLASS), BlockDB.LAYER_BLEND, "glass renders in the alpha blend layer")
	h.eq(BlockDB.layer_of(BlockDB.OAK_LEAVES), BlockDB.LAYER_CUTOUT, "leaves render in the cutout layer")
	h.eq(BlockDB.layer_of(BlockDB.PINE_LOG), BlockDB.LAYER_OPAQUE, "logs render opaque")
	h.check(BlockDB.is_deco(BlockDB.GRASS_TUFT), "grass tuft is decoration")
	h.check(not BlockDB.is_deco(BlockDB.OAK_LEAVES), "leaves are not decoration")

	# The mesher inlines this rule for speed; prove the inlined form matches the
	# helper for every block against every block, so the two cannot drift.
	var opaque := BlockDB.opaque
	var liquid := BlockDB.liquid
	var cull_same := BlockDB.cull_same
	var mismatches := 0
	for block_id in BlockDB.COUNT:
		var is_liquid := liquid[block_id] == 1
		var culls := cull_same[block_id] == 1
		for neighbour in BlockDB.COUNT:
			var inlined := false
			if neighbour != BlockDB.AIR:
				if is_liquid:
					inlined = liquid[neighbour] == 1
				elif opaque[neighbour] == 1:
					inlined = true
				elif neighbour == block_id and culls:
					inlined = true
			if inlined != BlockDB.hides_neighbour_face(block_id, neighbour):
				mismatches += 1
	h.eq(mismatches, 0, "the mesher's inlined face culling matches BlockDB for all %d block pairs" % (BlockDB.COUNT * BlockDB.COUNT))

	h.finish()
