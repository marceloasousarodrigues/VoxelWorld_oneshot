extends RefCounted

## M41c visual contract for the first-person hand and held tools.
##
## These checks deliberately test the construction and the presentation, not
## only that a mesh exists: the tool must have layered metal, a segmented haft,
## a grip origin inside the fist, and a screen footprint in the lower-right
## quadrant with the reticle clear.  Thresholds mirror the milestone acceptance
## standard and are not relaxed by the implementation.

const Visual = preload("res://scripts/game/held_item_visual.gd")
const Presentation = preload("res://scripts/game/item_presentation.gd")


func name() -> String:
	return "M41c held tool construction and grip"


func run(h: TestHarness) -> void:
	h.section("M41c held tool construction and grip")
	var library := TextureLibrary.new()
	h.check(library.load_all(), "the texture library loads")
	var tree := Engine.get_main_loop() as SceneTree
	var player = VoxelPlayer.new()
	player.texture_library = library
	player.inventory = Inventory.new()
	player.set_process(false)
	player.set_physics_process(false)
	tree.root.add_child(player)
	player.teleport_to(Vector3(8.5, 90.0, 8.5))
	player.look_yaw(20.0)
	player.look_pitch(-12.0)
	var view_size: Vector2 = player.camera.get_viewport().get_visible_rect().size

	var ids := [ItemDB.WOOD_PICKAXE, ItemDB.STONE_AXE,
		ItemDB.IRON_SHOVEL, ItemDB.DIAMOND_SWORD]
	for item_id: int in ids:
		player.inventory.clear_slot(0)
		player.inventory.add(item_id, 1)
		player.inventory.select(0)
		player.refresh_visuals()
		var held_root: Node = player.first_person_arms.get_node("RightArm/HeldItem")
		h.check(held_root != null and held_root.get_child_count() == 1,
			"%s has one held visual" % ItemDB.name_of(item_id))
		if held_root == null or held_root.get_child_count() != 1:
			continue
		var visual: Node3D = held_root.get_child(0)
		h.eq(int(visual.get("item_id")), item_id, "%s reports the real item id" % ItemDB.name_of(item_id))
		h.greater(visual.get_child_count(), 20,
			"%s is built from layered parts, not a single box" % ItemDB.name_of(item_id))

		var colours := _material_colours(visual)
		h.greater(colours.size(), 6,
			"%s separates metal, wood, leather and highlight materials" % ItemDB.name_of(item_id))
		var tool_bounds := _visual_bounds(visual)
		h.check(tool_bounds.has_point(Vector3.ZERO),
			"%s envelope contains the grip origin" % ItemDB.name_of(item_id))
		h.check(not _casts_shadows(visual),
			"%s casts no false first-person shadow" % ItemDB.name_of(item_id))

		h.check(player.first_person_arms.reticle_clear(),
			"%s rests clear of the reticle" % ItemDB.name_of(item_id))
		var screen: Rect2 = player.first_person_arms.screen_bounds(player.camera)
		var visible: Rect2 = screen.intersection(Rect2(Vector2.ZERO, view_size))
		h.greater(visible.position.x, view_size.x * 0.45,
			"%s stays on the right side of the frame" % ItemDB.name_of(item_id))
		h.greater(visible.position.y, view_size.y * 0.30,
			"%s stays in the lower part of the frame" % ItemDB.name_of(item_id))
		h.less(visible.size.x, view_size.x * 0.42,
			"%s keeps a restrained first-person width" % ItemDB.name_of(item_id))
		h.less(visible.size.y, view_size.y * 0.55,
			"%s keeps a restrained first-person height" % ItemDB.name_of(item_id))

		# The grip is one coherent assembly: the fist is built in the item's
		# frame and shares the grip origin.
		var hand: Node3D = player.first_person_arms.get_node("RightArm/GripHand")
		h.check(hand != null, "%s has a modelled grip hand" % ItemDB.name_of(item_id))
		if hand != null:
			h.approx(hand.position.distance_to((held_root as Node3D).position), 0.0, 0.0001,
				"%s fist and haft share one grip origin" % ItemDB.name_of(item_id))
			h.greater(hand.get_child_count(), 12, "%s fist has finger and wrist detail" % ItemDB.name_of(item_id))
			h.check(_visual_bounds(hand).has_point(Vector3.ZERO),
				"%s fist closes around the grip origin" % ItemDB.name_of(item_id))
			h.greater(_named_count(hand, "GripFinger"), 7,
				"%s fist has four finger wraps and side knuckles" % ItemDB.name_of(item_id))
			h.greater(_named_count(hand, "GripThumb"), 2,
				"%s fist has a modelled thumb across the grip" % ItemDB.name_of(item_id))

		# The swing keeps the assembly clear of the reticle for every tool.
		player.first_person_arms.play_swing()
		for step in 6:
			player.first_person_arms.animate(0.05, 5.0, true, 0.0)
			h.check(player.first_person_arms.reticle_clear(),
				"%s swing stays below the reticle at step %d" % [ItemDB.name_of(item_id), step])

	# --- class-specific silhouette checks ---------------------------------
	h.section("M41c tool silhouettes")
	var pick = _build(ItemDB.WOOD_PICKAXE, library)
	h.greater(_named_bounds(pick, "PickArm").size.x, _visual_bounds(pick).size.y * 0.72,
		"the pickaxe head is wider than two thirds of the whole tool")
	h.greater(_named_count(pick, "PickBoss"), 0, "the pickaxe has a raised central boss")
	h.greater(_named_count(pick, "PickRivet") + _named_count(pick, "PickHubRivet"), 5,
		"the pickaxe has selected rivets rather than none")
	h.greater(_named_count(pick, "PickTopBevel"), 1,
		"the pickaxe head has a lighter top bevel on both arms")
	h.greater(_named_count(pick, "GripWrap"), 4, "the pickaxe haft has a leather grip wrap")
	pick.free()

	var axe = _build(ItemDB.STONE_AXE, library)
	var axe_head := _named_bounds(axe, "AxeBlade")
	h.greater(axe_head.size.x, 0.18, "the axe blade has a broad silhouette")
	h.greater(axe_head.size.y, 0.13, "the axe blade has a tall bearded profile")
	h.greater(_named_count(axe, "AxeCheek"), 0, "the axe has an inset cheek plate")
	h.greater(_named_count(axe, "AxeEdge"), 0, "the axe has a bright cutting edge layer")
	axe.free()

	var shovel = _build(ItemDB.IRON_SHOVEL, library)
	h.greater(_named_bounds(shovel, "ShovelBlade").size.x, 0.14,
		"the shovel has a broad spade blade")
	h.greater(_named_count(shovel, "ShovelScoop"), 0, "the shovel has a recessed scoop face")
	h.greater(_named_count(shovel, "ShovelLip"), 0, "the shovel has a rolled bright lip")
	shovel.free()

	var sword = _build(ItemDB.DIAMOND_SWORD, library)
	h.greater(_named_bounds(sword, "Blade").size.y, 0.26, "the sword has a long blade")
	h.greater(_named_count(sword, "BladeEdge"), 1, "the sword has light edge strips on both sides")
	h.greater(_named_count(sword, "BladeFace") + _named_count(sword, "BladeRidge"), 1,
		"the sword blade has a layered face and ridge")
	sword.free()

	player.free()
	h.finish()


func _build(item_id: int, library: TextureLibrary) -> Node3D:
	var visual = Visual.new()
	visual.build(item_id, library, Presentation.item_size(item_id, false))
	(Engine.get_main_loop() as SceneTree).root.add_child(visual)
	return visual


func _visual_bounds(root: Node3D) -> AABB:
	var first := true
	var combined := AABB()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		var bounds: AABB = mesh.transform * mesh.get_aabb()
		if first:
			combined = bounds
			first = false
		else:
			combined = combined.merge(bounds)
	return combined


func _named_bounds(root: Node3D, prefix: String) -> AABB:
	var first := true
	var combined := AABB()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if not node.name.begins_with(prefix):
			continue
		var mesh := node as MeshInstance3D
		var bounds: AABB = mesh.transform * mesh.get_aabb()
		if first:
			combined = bounds
			first = false
		else:
			combined = combined.merge(bounds)
	return combined


func _named_count(root: Node3D, prefix: String) -> int:
	var count := 0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with(prefix):
			count += 1
	return count


func _material_colours(root: Node3D) -> Dictionary:
	var colours := {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		if material != null:
			colours[material.albedo_color.to_html(true)] = true
	return colours


func _casts_shadows(root: Node3D) -> bool:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return true
	return false
