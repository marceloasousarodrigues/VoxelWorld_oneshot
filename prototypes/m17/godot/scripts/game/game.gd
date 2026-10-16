extends Node3D

## VoxelWorld — native Godot 4 game entry point.
##
## This node owns the whole game: it builds the rendering environment, the
## authoritative voxel world, the streaming layer, the player, the HUD, the title
## screen and persistence, then drives them from a small state machine.
##
## It never builds voxel geometry itself: `ChunkStreamer` owns meshes and
## `VoxelWorld` owns voxel data.

enum State { MENU, LOADING, PLAYING, PAUSED }

const RESULTS_DIR := "res://../results/godot"
const CONFIG_PATH := "user://settings.json"
const AUTOSAVE_SECONDS := 120.0

var state := State.MENU

var library: TextureLibrary
var materials: VoxelMaterials
var mesher: ChunkMesher
var world: VoxelWorld
var fluid: FluidSim
var streamer: ChunkStreamer
var player: VoxelPlayer
var inventory: Inventory
var hud: GameHUD
var menu: MainMenu
var saves: SaveManager

var sun: DirectionalLight3D
var environment_node: WorldEnvironment

var _options := {
	"render_radius": 4,
	"vertical_radius": 4,
	"generation_budget": 8,
	"generation_budget_ms": 6.0,
	"mesh_budget": 3,
	"mesh_budget_ms": 8.0,
	"fluid_budget_ms": 2.0,
	"fluid_cells_per_tick": 1024,
	"shadow_distance": 96.0,
	"shadows": true,
	"fog_density": 0.0008,
	"capture": false,
	"capture_name": "godot-game-slice.png",
	"capture_settle": 12.0,
	"seed": 17017,
	"player_at": Vector3.INF,
	"look": Vector2(INF, INF),
	"straight_to_game": false,
	"hide_hud": false,
	"fly": false,
	"sun_angle": Vector2(-48.0, -132.0),
	"shots": [],
	"quit_after": 0.0,
	"quit_after_settle": false,
}

var _loading_seconds := 0.0
var _play_seconds := 0.0
var _total_seconds := 0.0
var _autosave_timer := 0.0
var _capture_timer := 0.0
var _frames := 0
var _fps_accumulator := 0.0
var _last_fps := 0.0
var _shots_taken := 0
var _stream_report_printed := false


# =========================================================================
# Boot
# =========================================================================

func _ready() -> void:
	_parse_arguments()
	library = TextureLibrary.new()
	if not library.load_all():
		push_error("VoxelWorld: block textures could not be loaded")
	materials = VoxelMaterials.new(library)
	mesher = ChunkMesher.new(library, materials)
	inventory = Inventory.new()
	saves = SaveManager.new()

	_build_environment()
	_build_nodes()
	_build_ui()

	if _options["straight_to_game"] or _options["capture"]:
		_start_world(int(_options["seed"]), null)
	else:
		_show_title()


func _build_environment() -> void:
	environment_node = WorldEnvironment.new()
	environment_node.name = "Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("2f7cc4")
	sky_material.sky_horizon_color = Color("cfe3e8")
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color("7f97a6")
	sky_material.ground_horizon_color = Color("c6d7dd")
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("8fb6d6")
	environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = 1.45
	environment.background_energy_multiplier = 0.95
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.6
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.02
	environment.adjustment_brightness = 1.02
	environment.fog_enabled = true
	environment.fog_light_color = Color("c3dae0")
	# A gentle exponential haze: enough to soften the edge of the loaded world
	# without washing out the landscape. `--fog=0` disables it for comparison
	# captures; `--fog=<density>` retunes it.
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = float(_options["fog_density"])
	environment.fog_sky_affect = 0.3
	environment.ssao_enabled = true
	environment.ssao_radius = 0.5
	environment.ssao_intensity = 0.85
	environment.ssao_power = 1.1
	environment.ssao_detail = 0.4
	environment_node.environment = environment
	add_child(environment_node)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	_set_sun_angles(float(_options["sun_angle"].x), float(_options["sun_angle"].y))
	sun.light_color = Color("fff4e2")
	sun.light_energy = 1.22
	sun.shadow_enabled = bool(_options["shadows"])
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = float(_options["shadow_distance"])
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.light_angular_distance = 1.2
	add_child(sun)


func _set_sun_angles(pitch: float, yaw: float) -> void:
	sun.rotation_degrees = Vector3(pitch, yaw, 0.0)


func _build_nodes() -> void:
	player = VoxelPlayer.new()
	player.name = "Player"
	player.gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	player.can_interact = false
	player.set_physics_process(false)
	player.set_process(false)
	add_child(player)

	streamer = ChunkStreamer.new()
	streamer.name = "ChunkStreamer"
	streamer.render_radius = int(_options["render_radius"])
	streamer.vertical_radius = int(_options["vertical_radius"])
	streamer.generation_budget = int(_options["generation_budget"])
	streamer.generation_millisecond_budget = float(_options["generation_budget_ms"])
	streamer.mesh_budget = int(_options["mesh_budget"])
	streamer.mesh_millisecond_budget = float(_options["mesh_budget_ms"])
	streamer.focus_node = player
	add_child(streamer)

	player.block_broken.connect(_on_block_broken)
	player.block_placed.connect(_on_block_placed)
	player.target_changed.connect(_on_target_changed)
	player.interaction_failed.connect(_on_interaction_failed)
	player.fly_changed.connect(_on_fly_changed)


func _build_ui() -> void:
	hud = GameHUD.new()
	hud.name = "HUD"
	hud.visible = not bool(_options["hide_hud"])
	add_child(hud)
	hud.setup(inventory, library)

	menu = MainMenu.new()
	menu.name = "Menu"
	add_child(menu)
	menu.new_world_requested.connect(func(seed_value: int) -> void: _start_world(seed_value, null))
	menu.continue_requested.connect(_continue_saved_world)
	menu.quit_requested.connect(func() -> void: get_tree().quit())
	menu.resume_requested.connect(_resume)
	menu.set_save_callback(_save_now)
	menu.set_title_callback(_return_to_title)


# =========================================================================
# Command line
# =========================================================================

func _parse_arguments() -> void:
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		# Echoed once so a capture run records exactly which options were applied.
		print("M17_ARGS %s" % " ".join(user_args))
	for argument: String in user_args:
		var parts := argument.split("=", true, 1)
		var key := parts[0].strip_edges()
		var value := parts[1].strip_edges() if parts.size() > 1 else ""
		match key:
			"--capture":
				_options["capture"] = true
				_options["straight_to_game"] = true
			"--capture-name":
				_options["capture_name"] = value
			"--settle":
				_options["capture_settle"] = value.to_float()
			"--seed":
				_options["seed"] = value.to_int()
			"--render-distance":
				_options["render_radius"] = maxi(1, value.to_int())
			"--vertical-radius":
				_options["vertical_radius"] = maxi(1, value.to_int())
			"--generation-budget":
				_options["generation_budget"] = maxi(0, value.to_int())
			"--generation-budget-ms":
				_options["generation_budget_ms"] = maxf(0.5, value.to_float())
			"--mesh-budget":
				_options["mesh_budget"] = maxi(0, value.to_int())
			"--mesh-budget-ms":
				_options["mesh_budget_ms"] = maxf(0.5, value.to_float())
			"--player-at":
				_options["player_at"] = _parse_vector(value)
			"--look":
				var look := value.split(",")
				if look.size() == 2:
					_options["look"] = Vector2(look[0].to_float(), look[1].to_float())
			"--sun":
				var sun_angles := value.split(",")
				if sun_angles.size() == 2:
					_options["sun_angle"] = Vector2(sun_angles[0].to_float(), sun_angles[1].to_float())
			"--shots":
				_options["shots"] = _parse_shots(value)
			"--straight-to-game":
				_options["straight_to_game"] = true
			"--hide-hud":
				_options["hide_hud"] = true
			"--fly":
				_options["fly"] = true
			"--no-shadows":
				_options["shadows"] = false
			"--fog":
				_options["fog_density"] = maxf(0.0, value.to_float())
			"--quit-after":
				_options["quit_after"] = value.to_float()


func _parse_vector(value: String) -> Vector3:
	var parts := value.split(",")
	if parts.size() != 3:
		return Vector3.INF
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


## `--shots="yaw:pitch:x,y,z; yaw:pitch; ..."` — a scripted camera tour used to
## capture several viewpoints from one run.
func _parse_shots(value: String) -> Array:
	var shots: Array = []
	for chunk: String in value.split(";", false):
		var fields := chunk.split(":")
		if fields.size() < 2:
			continue
		var shot := {
			"yaw": fields[0].to_float(),
			"pitch": fields[1].to_float(),
			"position": Vector3.INF,
		}
		if fields.size() >= 3:
			shot["position"] = _parse_vector(fields[2])
		shots.append(shot)
	return shots


# =========================================================================
# State machine
# =========================================================================

func _show_title() -> void:
	state = State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.set_title_callback(_return_to_title)
	var has_save := FileAccess.file_exists(saves.save_path())
	var note := "Saves are written to %s" % ProjectSettings.globalize_path(saves.directory)
	if has_save:
		note = "Existing save found: %s" % ProjectSettings.globalize_path(saves.save_path())
	menu.show_menu(has_save, note)


func _start_world(seed_value: int, save: Variant) -> void:
	menu.hide_menu()
	state = State.LOADING
	_loading_seconds = 0.0
	_play_seconds = 0.0
	_autosave_timer = 0.0
	_stream_report_printed = false

	world = VoxelWorld.new(seed_value)
	fluid = FluidSim.new(world)
	fluid.max_cells_per_tick = int(_options["fluid_cells_per_tick"])
	fluid.max_milliseconds_per_tick = float(_options["fluid_budget_ms"])
	world.block_changed.connect(fluid.on_block_changed)
	streamer.setup(world, mesher)
	player.world = world
	player.inventory = inventory
	mesher.stats["builds"] = 0
	mesher.stats["fill_ms"] = 0.0
	mesher.stats["emit_ms"] = 0.0
	mesher.stats["assemble_ms"] = 0.0
	streamer.stats["meshed"] = 0
	streamer.stats["faces"] = 0
	streamer.stats["mesh_ms"] = 0.0

	inventory.give_starter_kit()

	var spawn_column := _find_spawn_column()
	var eye_guess := world.generator.height_at(spawn_column.x, spawn_column.y)
	player.teleport_to(Vector3(spawn_column.x + 0.5, float(eye_guess) + 4.0, spawn_column.y + 0.5))
	player.look_yaw(38.0)
	player.look_pitch(-12.0)
	streamer.focus_at(player.global_position)

	if save != null:
		var applied: Dictionary = saves.apply(save, world, player, inventory)
		if not applied["ok"]:
			hud.flash("Save rejected: %s" % applied["error"], 6.0)
		else:
			streamer.focus_at(player.global_position)
			hud.flash("Loaded %d block edits and %d fluid changes" % [int(applied["block_edits"]), int(applied["fluid_edits"])], 5.0)
	_apply_override_position()
	player.set_process(true)
	var loading := "Generating world"
	if save != null:
		loading = "Loading world"
	hud.set_status("%s — seed %d" % [loading, seed_value])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_override_position() -> void:
	var override: Vector3 = _options["player_at"]
	if override.is_finite():
		player.teleport_to(override)
	var look: Vector2 = _options["look"]
	if look.is_finite():
		player.look_yaw(look.x)
		player.look_pitch(look.y)


## Picks a pleasant spawn: a land column near the origin that is above sea level.
func _find_spawn_column() -> Vector2i:
	var generator: WorldGen = world.generator
	for radius in range(0, 40):
		for step in range(-radius, radius + 1):
			for candidate: Vector2i in [
				Vector2i(8 + step, 8 - radius), Vector2i(8 + step, 8 + radius),
				Vector2i(8 - radius, 8 + step), Vector2i(8 + radius, 8 + step),
			]:
				var height := generator.height_at(candidate.x, candidate.y)
				if height < WorldGen.SEA_LEVEL + 1 or height > 96:
					continue
				var biome := generator.biome_at(candidate.x, candidate.y)
				if biome == WorldGen.Biome.OCEAN or biome == WorldGen.Biome.MOUNTAIN:
					continue
				return candidate
	return Vector2i(8, 8)


func _update_loading(delta: float) -> void:
	_loading_seconds += delta
	var spawn := ChunkStreamer.chunk_of(player.global_position)
	var ready := streamer.is_area_ready(player.global_position, 2)
	if not ready and _loading_seconds < 45.0:
		hud.set_status("Generating world — %d/%d chunks" % [streamer.loaded_count(), streamer.wanted_count()])
		hud.set_debug("seed %d  ·  %s  ·  %.1fs" % [world.world_seed, str(_center_biome_name()), _loading_seconds])
		return
	_enter_play(ready)


func _enter_play(area_ready: bool) -> void:
	player.spawn_on_column(int(floor(player.global_position.x)), int(floor(player.global_position.z)))
	_apply_override_position()
	player.can_interact = true
	player.set_physics_process(true)
	if bool(_options["fly"]) and not player.flying:
		# Inspection aid: `--fly` holds a teleported vantage point so a capture
		# tour can look at the world instead of falling to the ground first.
		player.flying = true
	state = State.PLAYING
	if not bool(_options["capture"]):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_status("")
	if not area_ready:
		hud.flash("World streaming is still catching up", 4.0)
	elif _play_seconds == 0.0 and not bool(_options["capture"]):
		hud.flash("VoxelWorld — seed %d" % world.world_seed, 4.0)
	print("M17_GAME_READY seed=%d player=%s chunks=%d views=%d meshed=%d" % [
		world.world_seed, player.global_position, streamer.loaded_count(), streamer.view_count(), int(streamer.stats["meshed"]),
	])


func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.can_interact = false
	player.velocity = Vector3.ZERO
	menu.set_save_callback(_save_now)
	menu.set_title_callback(_return_to_title)
	menu.show_pause()


func _resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	player.can_interact = true
	menu.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _return_to_title() -> void:
	_save_now()
	streamer.clear()
	player.teleport_to(Vector3(8.5, 120.0, 8.5))
	player.can_interact = false
	player.set_physics_process(false)
	_show_title()


func _continue_saved_world() -> void:
	var result := saves.read()
	if not result["ok"]:
		hud.flash("Could not load: %s" % result["error"], 6.0)
		if not menu.is_open():
			menu.show_menu(FileAccess.file_exists(saves.save_path()), result["error"])
		return
	_start_world(int(result["data"]["seed"]), result)


# =========================================================================
# Frame loop
# =========================================================================

func _process(delta: float) -> void:
	_frames += 1
	_total_seconds += delta
	_fps_accumulator += delta
	if _fps_accumulator >= 0.35:
		_last_fps = float(_frames) / _fps_accumulator
		_frames = 0
		_fps_accumulator = 0.0

	var quit_after := float(_options["quit_after"])
	if quit_after > 0.0 and _total_seconds >= quit_after and state in [State.PLAYING, State.LOADING]:
		_smoke_summary()
		get_tree().quit()
		return

	match state:
		State.LOADING:
			_update_loading(delta)
		State.PLAYING:
			_play_seconds += delta
			_autosave_timer += delta
			if fluid != null:
				fluid.tick()
			_update_status()
			if bool(_options["capture"]):
				_update_capture(delta)
			elif _autosave_timer >= AUTOSAVE_SECONDS:
				_autosave_timer = 0.0
				_save_silently("autosave")
		_:
			pass


func _update_status() -> void:
	var eye := player.eye_position()
	var cell := Vector3i(floori(eye.x), floori(eye.y), floori(eye.z))
	hud.set_status("VoxelWorld  ·  seed %d  ·  Godot %s" % [
		world.world_seed, Engine.get_version_info().get("string", "?"),
	])
	var target: Dictionary = player.target()
	var target_text := "Target: none"
	if target.get("hit", false):
		var block_cell: Vector3i = target["block"]
		target_text = "Target: %s (%d, %d, %d)" % [
			BlockDB.name_of(int(target["block_id"])), block_cell.x, block_cell.y, block_cell.z,
		]
	hud.set_debug("%s\nXYZ %.1f / %.1f / %.1f   %s   %s\nchunks %d/%d queued %d  ·  fluid queue %d  ·  %d fps%s" % [
		target_text,
		eye.x, eye.y, eye.z,
		_center_biome_name(),
		"flying" if player.flying else ("submerged" if player.is_submerged() else "walking"),
		streamer.loaded_count(), streamer.wanted_count(), streamer.queued_count(),
		fluid.pending_count() if fluid != null else 0,
		int(round(_last_fps)),
		"\nHUD hidden (F3 shows it)" if not hud.debug_visible() else "",
	])


func _center_biome_name() -> String:
	var cell := Vector3i(floori(player.global_position.x), floori(player.global_position.y), floori(player.global_position.z))
	return world.generator.biome_name(world.biome_at(cell.x, cell.z))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED:
			_resume()
	elif event.is_action_pressed("toggle_debug"):
		hud.toggle_debug()
	elif event.is_action_pressed("save_world"):
		_save_now()
	elif event.is_action_pressed("load_saved_world"):
		_reload_now()
	elif state == State.PLAYING:
		if event.is_action_pressed("toggle_fly"):
			player.toggle_fly()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_handle_hotbar_input(event)


func _handle_hotbar_input(event: InputEvent) -> void:
	for index in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("slot_%d" % (index + 1)):
			inventory.select(index)
			return


# =========================================================================
# Interaction
# =========================================================================

func _on_block_broken(world_position: Vector3i, block_id: int, drop: int) -> void:
	var collected := ""
	if drop != BlockDB.NO_DROP:
		var leftover := inventory.add(drop, 1)
		collected = "  +1 %s" % BlockDB.name_of(drop) if leftover == 0 else "  (inventory full)"
	hud.flash("Mined %s at (%d, %d, %d)%s" % [BlockDB.name_of(block_id), world_position.x, world_position.y, world_position.z, collected], 1.6)


func _on_block_placed(world_position: Vector3i, block_id: int) -> void:
	inventory.take_from_slot(inventory.selected)
	hud.flash("Placed %s at (%d, %d, %d)" % [BlockDB.name_of(block_id), world_position.x, world_position.y, world_position.z], 1.4)


func _on_target_changed(hit: Dictionary) -> void:
	pass


func _on_interaction_failed(reason: String) -> void:
	hud.flash(reason, 1.6)


func _on_fly_changed(enabled: bool) -> void:
	hud.flash("Flight %s" % ("enabled" if enabled else "disabled"), 1.4)


# =========================================================================
# Persistence
# =========================================================================

func _save_now() -> void:
	var written := saves.write(world, player, inventory)
	if written:
		hud.flash("Saved %d block edits to %s" % [world.edits.size(), ProjectSettings.globalize_path(saves.save_path())], 4.0)
		print("M17_GAME_SAVED path=%s block_edits=%d fluid_edits=%d" % [
			ProjectSettings.globalize_path(saves.save_path()), world.edits.size(), world.fluid_overrides.size(),
		])
	else:
		hud.flash("Save failed: %s" % saves.last_error, 5.0)
		push_error("M17_GAME_SAVE_FAILED %s" % saves.last_error)


func _save_silently(reason: String) -> void:
	if saves.write(world, player, inventory):
		print("M17_GAME_AUTOSAVE reason=%s block_edits=%d" % [reason, world.edits.size()])
	else:
		push_error("M17_GAME_AUTOSAVE_FAILED %s" % saves.last_error)


func _reload_now() -> void:
	var result := saves.read()
	if not result["ok"]:
		hud.flash("Load failed: %s" % result["error"], 5.0)
		return
	var applied: Dictionary = saves.apply(result["data"], world, player, inventory)
	if not applied["ok"]:
		hud.flash("Load failed: %s" % applied["error"], 5.0)
		return
	streamer.focus_at(player.global_position)
	hud.refresh()
	hud.flash("Reloaded save (%d block edits)" % int(applied["block_edits"]), 4.0)
	print("M17_GAME_LOADED block_edits=%d fluid_edits=%d" % [int(applied["block_edits"]), int(applied["fluid_edits"])])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and world != null and state in [State.PLAYING, State.PAUSED]:
		_save_silently("quit")


# =========================================================================
# Automated capture (visual verification harness)
# =========================================================================

## Stages: 0 = waiting for the world to stream in, 1 = settled, capture when the
## frame has rendered, 2 = waiting for a tour teleport to stream in.
var _capture_stage := 0
var _stage_timer := 0.0
var _shot_index := -1


func _update_capture(delta: float) -> void:
	_capture_timer += delta
	_stage_timer += delta
	var shots: Array = _options["shots"]
	match _capture_stage:
		0:
			if _stage_timer >= 1.0 and (streamer.is_settled() or _capture_timer >= float(_options["capture_settle"])):
				print("M17_STREAM_SETTLED %s" % JSON.stringify(streamer.report()))
				_capture_stage = 1
				_stage_timer = 0.0
			else:
				hud.set_status("Capturing in %.1fs — %d/%d chunks · queued %d" % [
					maxf(0.0, float(_options["capture_settle"]) - _capture_timer),
					streamer.loaded_count(), streamer.wanted_count(), streamer.queued_count(),
				])
		1:
			if _stage_timer < 1.4:
				return
			if _shot_index >= 0:
				await _save_capture(_shot_filename(_shot_index))
			_shot_index += 1
			if _shot_index >= maxi(1, shots.size()):
				_report_and_quit()
				return
			if not shots.is_empty():
				_apply_shot(shots[_shot_index])
				_capture_timer = 0.0
				_capture_stage = 2
			else:
				_capture_stage = 2
			_stage_timer = 0.0
		2:
			if _stage_timer >= 0.8 and (streamer.is_settled() or _capture_timer >= 8.0):
				_capture_stage = 1
				_stage_timer = 0.0


func _shot_filename(index: int) -> String:
	if (_options["shots"] as Array).is_empty():
		return str(_options["capture_name"])
	return "godot-game-tour-%d.png" % index


func _apply_shot(shot: Dictionary) -> void:
	var position: Vector3 = shot["position"]
	if position.is_finite():
		player.teleport_to(position)
	player.look_yaw(float(shot["yaw"]))
	player.look_pitch(float(shot["pitch"]))


func _report_and_quit() -> void:
	_smoke_summary()
	print("M17_CAPTURE_METRICS %s" % _write_capture_metrics())
	get_tree().quit()


## One line of machine-readable state, used by both the capture harness and the
## headless smoke run.
func _smoke_summary() -> void:
	print("M17_GAME_SUMMARY %s" % JSON.stringify({
		"state": State.keys()[state],
		"seed": world.world_seed if world != null else -1,
		"player": [player.global_position.x, player.global_position.y, player.global_position.z],
		"eye": [player.eye_position().x, player.eye_position().y, player.eye_position().z],
		"look": [player.look_angles().x, player.look_angles().y],
		"biome": _center_biome_name() if world != null else "",
		"fps": _last_fps,
		"streaming": streamer.report() if streamer != null else {},
		"world_hash": world.fingerprint() if world != null else -1,
		"fluid": fluid.stats() if fluid != null else {},
		"mesher": mesher.stats,
		"edits": world.edits.size() if world != null else -1,
		"inventory_used_slots": inventory.used_slots(),
	}))
	print("M17_RENDER_STATS draw_calls=%d primitives=%d objects=%d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
	])


func _save_capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path(RESULTS_DIR)
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(filename)
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("M17_CAPTURE_FAILED %s (error %d)" % [path, error])
		return
	print("M17_SCREENSHOT_SAVED %s %dx%d" % [path, image.get_width(), image.get_height()])


func _write_capture_metrics() -> String:
	var directory := ProjectSettings.globalize_path(RESULTS_DIR)
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("game-capture.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return path
	file.store_string(JSON.stringify({
		"evidence": "offscreen Godot viewport PNG written from inside the running game scene; not a human visual inspection",
		"godot_version": Engine.get_version_info(),
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"fps_last_sample": _last_fps,
		"seed": world.world_seed,
		"player": [player.global_position.x, player.global_position.y, player.global_position.z],
		"eye": [player.eye_position().x, player.eye_position().y, player.eye_position().z],
		"look": [player.look_angles().x, player.look_angles().y],
		"biome": _center_biome_name(),
		"world_hash": world.fingerprint(),
		"streaming": streamer.report(),
		"fluid": fluid.stats(),
		"mesher": mesher.stats,
	}, "\t") + "\n")
	file.close()
	return path
