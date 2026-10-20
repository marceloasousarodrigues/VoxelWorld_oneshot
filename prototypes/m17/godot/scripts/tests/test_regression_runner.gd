extends RefCounted

func name() -> String:
	return "regression runner API"


func run(h: TestHarness) -> void:
	var script: Variant = load("res://scripts/regression.gd")
	h.check(script is GDScript and (script as GDScript).can_instantiate(),
		"the standalone regression runner parses and instantiates")
	for block_id: int in [BlockDB.GRASS, BlockDB.DIRT, BlockDB.STONE, BlockDB.WATER]:
		h.check(not BlockDB.name_of(block_id).is_empty(),
			"the runner's shared palette block %d has a canonical name" % block_id)
	var source := FileAccess.open("res://scripts/regression.gd", FileAccess.READ)
	h.check(source != null, "the standalone regression runner source is readable")
	if source != null:
		var contents := source.get_as_text()
		for stale_reference: String in ["world.GRASS", "world.DIRT", "world.STONE", "world.WATER",
				"world.AIR", "world.MATERIAL_NAMES"]:
			h.check(not contents.contains(stale_reference),
				"the runner does not access stale VoxelWorld symbol %s" % stale_reference)
	h.finish()
