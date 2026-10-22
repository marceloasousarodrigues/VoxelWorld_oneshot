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
	h.eq(BlockDB.names.size(), BlockDB.COUNT, "every id slot is addressable")
	h.eq(BlockDB.face_keys.size(), BlockDB.COUNT, "every id slot has a face entry")
	h.eq(BlockDB._defined_total(), BlockDB.DEFINED_COUNT, "exactly the real blocks are defined")
	h.check(BlockDB.is_defined(BlockDB.CHEST), "the storage chest is a defined block")
	h.check(BlockDB.is_defined(BlockDB.FARMLAND), "farmland is a defined block")
	h.check(BlockDB.is_defined(BlockDB.WHEAT_3), "a ripe wheat crop is a defined block")
	h.check(not BlockDB.is_defined(ItemDB.STICK), "a material id is not a block")
	h.check(not BlockDB.is_solid(ItemDB.STICK), "a material id is not solid")
	h.check(not BlockDB.is_deco(ItemDB.STICK), "a material id is not decoration")
	h.check(BlockDB.is_deco(BlockDB.WHEAT_1), "a growing crop is decoration")
	h.check(BlockDB.is_breakable(BlockDB.WHEAT_3), "a ripe crop can be harvested by breaking it")
	h.eq(BlockDB.drop_of(BlockDB.CHEST), BlockDB.CHEST, "a chest drops itself")
	h.eq(BlockDB.drop_of(BlockDB.WHEAT_3), BlockDB.NO_DROP, "a crop's loot comes from the farming rule, not the block drop")
	h.check(BlockDB.is_open_model(BlockDB.CHEST), "the chest custom model does not hide neighbouring faces")

	# M22 vegetation and architecture blocks.
	h.check(BlockDB.is_defined(BlockDB.BIRCH_LOG), "the birch log is a defined block")
	h.check(BlockDB.is_defined(BlockDB.BLOSSOM_LEAVES), "blossom leaves are a defined block")
	h.check(BlockDB.is_deco(BlockDB.FLOWER_RED), "a flower is decoration")
	h.check(BlockDB.is_flower(BlockDB.FLOWER_BLUE), "flower identity is exposed for tint exclusion")
	h.check(not BlockDB.is_flower(BlockDB.BUSH), "a bush is not a flower")
	h.eq(BlockDB.layer_of(BlockDB.BIRCH_LEAVES), BlockDB.LAYER_CUTOUT, "birch leaves render in the cutout layer")
	h.eq(BlockDB.layer_of(BlockDB.FLOWER_YELLOW), BlockDB.LAYER_DECO, "flowers render in the decoration layer")
	h.check(BlockDB.is_custom_model(BlockDB.LANTERN), "the lantern has a custom one-cell model")
	h.check(BlockDB.is_custom_model(BlockDB.FENCE), "the fence has a custom one-cell model")
	h.check(BlockDB.is_custom_model(BlockDB.BARREL), "the barrel has a custom one-cell model")
	h.check(not BlockDB.is_solid(BlockDB.LANTERN), "a hanging lantern is non-solid")
	h.check(BlockDB.is_solid(BlockDB.FENCE), "a fence still blocks movement")
	h.check(BlockDB.is_open_model(BlockDB.LANTERN), "the lantern does not cull its neighbours' faces")
	h.eq(BlockDB.drop_of(BlockDB.TIMBER_FRAME), BlockDB.TIMBER_FRAME, "timber framing drops itself")
	h.eq(BlockDB.drop_of(BlockDB.DOOR), BlockDB.DOOR, "a door drops itself")
	h.check(not BlockDB.is_defined(ItemDB.RAW_MEAT), "the M21 item range is still not a block range")
	h.check(not BlockDB.is_defined(ItemDB.BONE_MEAL), "the last M21 item id is still not a block")

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
	h.check(BlockDB.hides_neighbour_face(BlockDB.WATER, BlockDB.STONE), "water culls its face against solid stone")
	h.check(BlockDB.hides_neighbour_face(BlockDB.GLASS, BlockDB.GLASS), "glass culls its equal neighbours")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.GLASS, BlockDB.AIR), "glass face is visible against air")
	h.check(BlockDB.hides_neighbour_face(BlockDB.OAK_LEAVES, BlockDB.OAK_LEAVES), "canopy interior faces are culled")
	h.check(BlockDB.hides_neighbour_face(BlockDB.OAK_LEAVES, BlockDB.STONE), "opaque neighbours hide leaves faces")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.GRASS, BlockDB.OAK_LEAVES), "grass face stays visible next to leaves")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.STONE, BlockDB.CRAFTING_TABLE),
		"the open crafting-table model does not hide the block below it")
	h.check(not BlockDB.hides_neighbour_face(BlockDB.STONE, BlockDB.FURNACE),
		"the furnace model does not hide neighbouring faces")
	h.check(BlockDB.is_open_model(BlockDB.CRAFTING_TABLE), "the crafting table is an open render model")
	h.check(BlockDB.is_open_model(BlockDB.FURNACE), "the furnace is an open render model")
	h.check(not BlockDB.is_open_model(BlockDB.STONE), "stone is a full cube")

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
	var open_model := BlockDB.open_model
	var mismatches := 0
	for block_id in BlockDB.COUNT:
		var is_liquid := liquid[block_id] == 1
		var culls := cull_same[block_id] == 1
		for neighbour in BlockDB.COUNT:
			var inlined := false
			if neighbour != BlockDB.AIR:
				if is_liquid:
					inlined = true
				elif opaque[neighbour] == 1:
					inlined = open_model[neighbour] == 0
				elif neighbour == block_id and culls:
					inlined = true
			if inlined != BlockDB.hides_neighbour_face(block_id, neighbour):
				mismatches += 1
	h.eq(mismatches, 0, "the mesher's inlined face culling matches BlockDB for all %d block pairs" % (BlockDB.COUNT * BlockDB.COUNT))

	h.finish()
