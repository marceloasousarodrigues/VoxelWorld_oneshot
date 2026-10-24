extends RefCounted

## Player visual contract: first person is the default, arms and the held item
## are camera-local and clear of the reticle, the third-person body is a real
## articulated model, and switching never mutates gameplay state.

const Preview = preload("res://scripts/game/character_preview.gd")


func name() -> String:
	return "player first/third-person visuals"


func run(h: TestHarness) -> void:
	h.section("player visual modes")
	var library := TextureLibrary.new()
	h.check(library.load_all(), "the item texture library loads for held-item visuals")
	var player = VoxelPlayer.new()
	player.texture_library = library
	player.inventory = Inventory.new()
	player.set_process(false)
	player.set_physics_process(false)
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.teleport_to(Vector3(8.5, 90.0, 8.5))
	player.look_yaw(20.0)
	player.look_pitch(-12.0)

	# --- default first-person view ----------------------------------------
	h.eq(player.camera_mode, VoxelPlayer.CAMERA_FIRST, "first person is the default camera mode")
	h.check(player.camera.current, "the first-person camera is current by default")
	h.check(player.first_person_arms.visible, "the camera arms are visible in first person")
	h.check(not player.character.visible, "the third-person body is hidden in first person")
	h.check(player.first_person_arms.reticle_clear(),
		"the arms and hands stay clear of the aiming reticle")
	var view_size: Vector2 = player.camera.get_viewport().get_visible_rect().size
	var arm_bounds: Rect2 = player.first_person_arms.screen_bounds(player.camera)
	var visible_arm_bounds := arm_bounds.intersection(Rect2(Vector2.ZERO, view_size))
	h.greater(visible_arm_bounds.position.x, view_size.x * 0.45,
		"the resting hand enters from the right side of the frame")
	h.greater(visible_arm_bounds.position.y, view_size.y * 0.30,
		"the resting hand enters from the lower part of the frame")
	h.less(visible_arm_bounds.size.x, view_size.x * 0.42,
		"the visible first-person arm occupies less than 42% of the frame width")
	h.less(visible_arm_bounds.size.y, view_size.y * 0.55,
		"the visible first-person arm occupies less than 55% of the frame height")
	for node: Node in player.first_person_arms.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var aabb := mesh.get_aabb()
		var min_screen := Vector2(INF, INF)
		var max_screen := Vector2(-INF, -INF)
		for corner in 8:
			var point := aabb.position + Vector3(
				aabb.size.x if corner & 1 else 0.0,
				aabb.size.y if corner & 2 else 0.0,
				aabb.size.z if corner & 4 else 0.0)
			var screen: Vector2 = player.camera.unproject_position(mesh.to_global(point))
			min_screen = min_screen.min(screen)
			max_screen = max_screen.max(screen)
		print("ARM_DEBUG %s size=%s screen=%s" % [mesh.name, str(aabb.size), str(max_screen - min_screen)])

	var arms_shadowed := false
	for node: Node in player.first_person_arms.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			arms_shadowed = true
	h.check(not arms_shadowed, "no first-person arm part casts a shadow")

	# --- third-person view -------------------------------------------------
	var yaw_before: float = player.rotation.y
	var pitch_before: float = player.camera.rotation.x
	player.toggle_camera_mode()
	h.eq(player.camera_mode, VoxelPlayer.CAMERA_THIRD, "the view toggles to third person")
	h.check(player.third_person_camera.current, "the third-person camera becomes current")
	player._sync_camera_rig(1.0)
	h.check(player.character.visible, "the full character is visible in third person")
	h.check(not player.first_person_arms.visible, "the camera arms are hidden in third person")
	h.approx(player.rotation.y, yaw_before, 1e-6, "switching views keeps the player yaw")
	h.approx(player.camera.rotation.x, pitch_before, 1e-6, "switching views keeps the player pitch")
	h.approx(player.character.rotation.y, PI, 1e-5,
		"the body faces the controller's -Z forward direction")
	h.greater(player.character.model_height(), 1.9, "the character is a full-height voxel body")
	h.less(player.character.model_height(), 2.3, "the character keeps the established stylised scale")

	# Rear camera aim is the same look direction as the first-person camera.
	var forward: Vector3 = -player.camera.global_basis.z
	h.greater(player.aim_direction().dot(forward), 0.99,
		"third-person aiming follows the same look direction as first person")
	player._sync_camera_rig(1.0)
	h.greater(player.current_camera_distance(), 1.0, "the third-person camera sits behind the body")
	h.less(player.current_camera_distance(), player.camera_distance + 1e-4,
		"the third-person camera respects the configured distance")
	player.third_person_camera.force_update_transform()
	var head_screen: Vector2 = player.third_person_camera.unproject_position(
		player.character.global_position + Vector3.UP * 1.78)
	h.less(head_screen.x, view_size.x * 0.5 - 18.0,
		"the character sits clearly left of the screen-centre crosshair")
	var focus: Vector3 = player.third_person_camera.global_position \
		- player.third_person_camera.global_basis.z \
		* (player.current_camera_distance() + player.reach)
	var focus_screen: Vector2 = player.third_person_camera.unproject_position(focus)
	h.less(absf(focus_screen.x - view_size.x * 0.5), 2.0,
		"the third-person camera's crosshair focus is centred horizontally")
	h.less(absf(focus_screen.y - view_size.y * 0.5), 2.0,
		"the third-person camera's crosshair focus is centred vertically")
	var aim_to_focus: Vector3 = (focus - player.eye_position()).normalized()
	h.greater(player.aim_direction().dot(aim_to_focus), 0.9999,
		"camera offset still aims from the player's eye through the crosshair")

	# Repeated switching is stable and always restores a valid current camera.
	for index in 11:
		player.toggle_camera_mode()
		h.check(player.camera.current != player.third_person_camera.current,
			"exactly one camera is current after toggle %d" % (index + 1))
	h.eq(player.camera_mode, VoxelPlayer.CAMERA_FIRST, "an odd/even number of toggles returns the expected mode")

	# --- the held item follows the hotbar in both views --------------------
	player.set_camera_mode(VoxelPlayer.CAMERA_THIRD)
	player.inventory.add(ItemDB.WOOD_PICKAXE, 1)
	player.inventory.select(0)
	player.refresh_visuals()
	h.eq(player.first_person_arms.held_item_id(), ItemDB.WOOD_PICKAXE,
		"the first-person arms receive the held tool")
	h.eq(player.character.held_item_id(), ItemDB.WOOD_PICKAXE,
		"the third-person body receives the held tool")
	h.check(player.character.has_held_item(), "the third-person character visibly holds the item")

	player.set_camera_mode(VoxelPlayer.CAMERA_FIRST)
	player.inventory.clear_slot(0)
	player.inventory.add(BlockDB.STONE, 8)
	player.inventory.select(0)
	player.refresh_visuals()
	h.eq(player.first_person_arms.held_item_id(), BlockDB.STONE,
		"the first-person hand switches to the newly selected block")
	var held_root: Node = player.first_person_arms.get_node_or_null("RightArm/HeldItem")
	h.check(held_root != null and held_root.get_child_count() == 1,
		"the first-person hand has exactly one held-item visual")
	if held_root != null and held_root.get_child_count() == 1:
		h.check(bool(held_root.get_child(0).cube), "a placeable block is built as a real cube")

	# The tool models are deliberately detailed, not uniform boxes.  Count the
	# separate parts and check the larger sword still stays below the reticle.
	player.inventory.clear_slot(0)
	player.inventory.add(ItemDB.DIAMOND_SWORD, 1)
	player.inventory.select(0)
	player.refresh_visuals()
	var sword_root: Node = player.first_person_arms.get_node_or_null("RightArm/HeldItem")
	h.check(sword_root != null and sword_root.get_child_count() == 1,
		"the first-person hand rebuilds the held sword")
	if sword_root != null and sword_root.get_child_count() == 1:
		var sword_visual: Node = sword_root.get_child(0)
		h.greater(sword_visual.get_child_count(), 10,
			"the sword is built from multiple silhouette and material parts")
		h.eq(int(sword_visual.get("item_id")), ItemDB.DIAMOND_SWORD,
			"the detailed model still reports the real selected item")
	h.check(player.first_person_arms.reticle_clear(),
		"the longer sword model still clears the reticle")
	var sword_bounds: Rect2 = player.first_person_arms.screen_bounds(player.camera)
	var visible_sword_bounds := sword_bounds.intersection(Rect2(Vector2.ZERO, view_size))
	h.less(visible_sword_bounds.size.x, view_size.x * 0.50,
		"the sword remains a held prop rather than spanning the view")
	h.greater(visible_sword_bounds.position.x, view_size.x * 0.40,
		"the sword stays in the right side of the frame")

	# The swing pose must not block the reticle either.
	for index in 8:
		player.first_person_arms.play_swing()
		player.first_person_arms.animate(0.05, 5.0, true, 0.0)
		h.check(player.first_person_arms.reticle_clear(),
			"the swinging arm stays clear of the reticle at step %d" % index)

	# The same shared model is what the inventory preview instantiates.
	var preview = Preview.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(preview)
	preview.setup()
	h.check(not preview.is_rendering() or preview.get_node_or_null("PreviewViewport") != null,
		"the character preview uses the shared model viewport")
	preview.free()

	player.free()
	h.finish()
