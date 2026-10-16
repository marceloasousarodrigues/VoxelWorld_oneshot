extends Node3D

## VoxelWorld — native Godot 4 game entry point.
##
## This node owns the whole game: it builds the rendering environment, the
## authoritative voxel world, the streaming layer, the player, the HUD, the title
## screen and persistence, then drives them from a small state machine.
##
## It never builds voxel geometry itself: `ChunkStreamer` owns meshes and
## `VoxelWorld` owns voxel data.

enum State { MENU, LOADING, PLAYING, PAUSED, DEAD }

const RESULTS_DIR := "res://../results/godot"
const CONFIG_PATH := "user://settings.json"
const AUTOSAVE_SECONDS := 120.0
## After any damage the player is briefly immune to further *impact* damage, so a
## single landing or hit cannot apply twice in consecutive frames.
const IFRAME_SECONDS := 0.5

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
var crafting: CraftingPanel
var death_screen: DeathScreen
var saves: SaveManager
var health: Health

## Seconds of breath left; drained while the player's head is under water.
var breath := Survival.MAX_BREATH

var sun: DirectionalLight3D
var environment_node: WorldEnvironment
var environment: Environment
var sky_material: ProceduralSkyMaterial

var clock: DayNight

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
	"time_of_day": 0.28,
	"time_rate": 1.0,
	"capture": false,
	"capture_name": "godot-game-slice.png",
	"capture_settle": 12.0,
	"seed": 17017,
	"player_at": Vector3.INF,
	"look": Vector2(INF, INF),
	"straight_to_game": false,
	"hide_hud": false,
	"fly": false,
	"open_crafting": false,
	"sun_angle": Vector2(-48.0, -132.0),
	"shots": [],
	"quit_after": 0.0,
	"quit_after_settle": false,
	"health": -1.0,
	"hurt": -1.0,
	"submerge": false,
}

## Set when `--time-rate=` appears on the command line, so the capture harness
## only freezes the clock when the caller did not ask for a specific rate.
var _time_rate_given := false
## Set when `--sun=` pins the light direction; otherwise the clock drives it.
var _sun_angle_locked := false

## Health bookkeeping owned by the game layer: the invulnerability window and how
## long it has been since the last hit (which drives natural regeneration).
var _invulnerable := 0.0
var _seconds_since_damage := 0.0
var _last_damage_source := ""

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
	if bool(_options["capture"]) and not _time_rate_given:
		# A capture is evidence: freeze the clock at the requested time of day
		# unless the caller explicitly asked for a running clock.
		_options["time_rate"] = 0.0
	clock = DayNight.new(float(_options["time_of_day"]), _cycle_length())
	library = TextureLibrary.new()
	if not library.load_all():
		push_error("VoxelWorld: block textures could not be loaded")
	materials = VoxelMaterials.new(library)
	mesher = ChunkMesher.new(library, materials)
	inventory = Inventory.new()
	saves = SaveManager.new()
	health = Health.new()

	_build_environment()
	_build_nodes()
	_build_ui()

	if _options["straight_to_game"] or _options["capture"]:
		_start_world(int(_options["seed"]), null)
	else:
		_show_title()


func _cycle_length() -> float:
	var rate := float(_options["time_rate"])
	if rate <= 0.0:
		return 0.0
	return DayNight.DAY_LENGTH_SECONDS / rate


func _build_environment() -> void:
	environment_node = WorldEnvironment.new()
	environment_node.name = "Environment"
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = clock.sky_top_color()
	sky_material.sky_horizon_color = clock.sky_horizon_color()
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = clock.ground_bottom_color()
	sky_material.ground_horizon_color = clock.ground_horizon_color()
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = clock.ambient_color()
	environment.ambient_light_sky_contribution = clock.ambient_sky_contribution()
	environment.ambient_light_energy = clock.ambient_energy()
	environment.background_energy_multiplier = 0.95
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.6
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.02
	environment.adjustment_brightness = 1.02
	environment.fog_enabled = true
	environment.fog_light_color = clock.fog_color()
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
	sun.light_color = clock.sun_color()
	sun.light_energy = clock.sun_energy()
	sun.shadow_enabled = bool(_options["shadows"])
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = float(_options["shadow_distance"])
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.light_angular_distance = 1.2
	add_child(sun)


## Pushes the clock's lighting into the live environment.  Called every frame in
## the playing state; the values are pure functions of the time of day, so a
## frozen clock produces a byte-identical frame.
func _update_sky() -> void:
	if clock == null or sun == null:
		return
	var angles := clock.sun_angles()
	if not _sun_angle_locked:
		_set_sun_angles(angles.x, angles.y)
	sun.light_color = clock.sun_color()
	sun.light_energy = clock.sun_energy()
	environment.ambient_light_energy = clock.ambient_energy()
	environment.ambient_light_color = clock.ambient_color()
	environment.ambient_light_sky_contribution = clock.ambient_sky_contribution()
	environment.fog_light_color = clock.fog_color()
	if sky_material != null:
		sky_material.sky_top_color = clock.sky_top_color()
		sky_material.sky_horizon_color = clock.sky_horizon_color()
		sky_material.ground_bottom_color = clock.ground_bottom_color()
		sky_material.ground_horizon_color = clock.ground_horizon_color()
	var water := materials.water_material()
	if water != null:
		water.set_shader_parameter("water_tint", clock.water_tint())


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
	player.landed.connect(_on_landed)


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

	# The crafting panel lives on its own layer between the HUD (10) and the
	# menu (20), so its rows draw above the hotbar but the pause menu still
	# covers it.
	var crafting_layer := CanvasLayer.new()
	crafting_layer.name = "CraftingLayer"
	crafting_layer.layer = 15
	add_child(crafting_layer)
	crafting = CraftingPanel.new()
	crafting.name = "CraftingPanel"
	crafting_layer.add_child(crafting)
	crafting.setup(inventory)
	crafting.crafted.connect(_on_crafted)

	# The death screen sits above the HUD and the crafting panel but below the
	# menu (20), and owns the screen while the player is dead.
	var death_layer := CanvasLayer.new()
	death_layer.name = "DeathLayer"
	death_layer.layer = 18
	add_child(death_layer)
	death_screen = DeathScreen.new()
	death_screen.name = "DeathScreen"
	death_layer.add_child(death_screen)
	death_screen.respawn_requested.connect(_respawn)

	health.changed.connect(_on_health_changed)
	health.damaged.connect(_on_health_damaged)
	health.died.connect(_on_health_died)
	_on_health_changed()


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
					_sun_angle_locked = true
			"--time":
				_options["time_of_day"] = fposmod(value.to_float(), 1.0)
			"--time-rate":
				_options["time_rate"] = maxf(0.0, value.to_float())
				_time_rate_given = true
			"--shots":
				_options["shots"] = _parse_shots(value)
			"--straight-to-game":
				_options["straight_to_game"] = true
			"--open-crafting":
				_options["open_crafting"] = true
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
			"--health":
				_options["health"] = value.to_float()
			"--hurt":
				_options["hurt"] = maxf(0.0, value.to_float())
			"--submerge":
				# Inspection aid: put the camera under water so drowning and the
				# breath readout can be captured.  It implies `--fly` so the body
				# stays put instead of sinking to the sea floor.
				_options["submerge"] = true
				_options["fly"] = true


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
	if crafting != null and crafting.is_open():
		crafting.close()
	if death_screen != null and death_screen.is_open():
		death_screen.hide_death()
	menu.set_title_callback(_return_to_title)
	var has_save := FileAccess.file_exists(saves.save_path())
	var note := "Saves are written to %s" % ProjectSettings.globalize_path(saves.directory)
	if has_save:
		note = "Existing save found: %s" % ProjectSettings.globalize_path(saves.save_path())
	menu.show_menu(has_save, note)


func _start_world(seed_value: int, save: Variant) -> void:
	menu.hide_menu()
	if crafting != null and crafting.is_open():
		crafting.close()
	state = State.LOADING
	_loading_seconds = 0.0
	_play_seconds = 0.0
	_autosave_timer = 0.0
	_stream_report_printed = false
	clock = DayNight.new(float(_options["time_of_day"]), _cycle_length())
	_update_sky()
	health.revive()
	breath = Survival.MAX_BREATH
	_invulnerable = 0.0
	_seconds_since_damage = 0.0
	_last_damage_source = ""

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
		var applied: Dictionary = saves.apply(save, world, player, inventory, clock, health)
		if not applied["ok"]:
			hud.flash("Save rejected: %s" % applied["error"], 6.0)
		else:
			if float(applied["breath"]) >= 0.0:
				breath = float(applied["breath"])
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
	if bool(_options["submerge"]):
		player.teleport_to(_find_submersion_spot())
		player.flying = true
	var look: Vector2 = _options["look"]
	if look.is_finite():
		player.look_yaw(look.x)
		player.look_pitch(look.y)


## Inspection aid for `--submerge`: the deepest ocean column within a bounded
## search around the origin.  Deterministic for a given seed.
func _find_submersion_spot() -> Vector3:
	var generator: WorldGen = world.generator
	var best := Vector2i(8, 8)
	var best_height := 1 << 30
	for x in range(-64, 65):
		for z in range(-64, 65):
			var height := generator.height_at(x, z)
			if height >= WorldGen.SEA_LEVEL - 2:
				continue
			if generator.biome_at(x, z) != WorldGen.Biome.OCEAN:
				continue
			if height < best_height:
				best_height = height
				best = Vector2i(x, z)
	if best_height == (1 << 30):
		# No ocean nearby: float just below sea level in a known water column.
		return Vector3(8.5, float(WorldGen.SEA_LEVEL) - 4.0, 8.5)
	# Feet two blocks above the sea floor: the eye sits well under the surface.
	return Vector3(best.x + 0.5, float(best_height) + 2.0, best.y + 0.5)


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
	if bool(_options["open_crafting"]):
		_open_crafting()
	print("M17_GAME_READY seed=%d player=%s chunks=%d views=%d meshed=%d" % [
		world.world_seed, player.global_position, streamer.loaded_count(), streamer.view_count(), int(streamer.stats["meshed"]),
	])
	_apply_health_option()
	_apply_hurt_option()


## `--health=N` sets the starting health by dealing the difference, so a lethal
## value reaches the same death path as any other damage.
func _apply_health_option() -> void:
	var target := float(_options["health"])
	if target < 0.0:
		return
	var clamped := clampf(target, 0.0, health.max_health)
	if clamped < health.health:
		_damage(health.health - clamped, "startup")
	elif clamped > health.health:
		health.heal(clamped - health.health)


## `--hurt=N` applies one burst of damage as play starts; a value at or above the
## player's health reaches the death screen.
func _apply_hurt_option() -> void:
	var amount := float(_options["hurt"])
	if amount > 0.0:
		_damage(amount, "startup")


func _pause() -> void:
	if state != State.PLAYING:
		return
	if crafting != null and crafting.is_open():
		crafting.close()
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
	if quit_after > 0.0 and _total_seconds >= quit_after and state in [State.PLAYING, State.LOADING, State.DEAD]:
		_smoke_summary()
		get_tree().quit()
		return

	match state:
		State.LOADING:
			_update_loading(delta)
		State.PLAYING:
			_play_seconds += delta
			_autosave_timer += delta
			clock.advance(delta)
			_update_sky()
			if fluid != null:
				fluid.tick()
			_update_survival(delta)
			_update_status()
			if not bool(_options["capture"]) and _autosave_timer >= AUTOSAVE_SECONDS:
				_autosave_timer = 0.0
				_save_silently("autosave")
		_:
			pass
	# The capture harness also has to run on the death screen, so it is driven
	# from every "world is up" state rather than from the playing branch.
	if bool(_options["capture"]) and state in [State.PLAYING, State.DEAD]:
		_update_capture(delta)


## Per-frame survival: drowning while submerged, natural regeneration otherwise,
## and the breath readout.  Falls are event-driven (`player.landed`).
func _update_survival(delta: float) -> void:
	if health == null:
		return
	_invulnerable = maxf(0.0, _invulnerable - delta)
	_seconds_since_damage += delta
	var submerged := player.is_submerged()
	var step: Dictionary = Survival.breath_step(breath, Survival.MAX_BREATH, submerged, delta)
	breath = step["breath"]
	if float(step["damage"]) > 0.0:
		_damage(float(step["damage"]), "drowning")
	var regen: Dictionary = Survival.regen_step(health.health, health.max_health, _seconds_since_damage, delta)
	if float(regen["healed"]) > 0.0:
		health.heal(float(regen["healed"]))
	hud.set_breath(breath, Survival.MAX_BREATH, submerged or breath < Survival.MAX_BREATH - 0.001)


# =========================================================================
# Health and death
# =========================================================================

## Applies damage and returns what was applied.  All damage flashes the screen;
## the caller decides whether it is an *impact* (which also shakes).
func _damage(amount: float, source: String) -> float:
	if health == null or health.is_dead():
		return 0.0
	var applied := health.apply_damage(amount, source)
	if applied <= 0.0:
		return 0.0
	_seconds_since_damage = 0.0
	if hud != null:
		hud.hurt_flash()
	return applied


## Damage from a discrete impact (a fall, later a hit).  The invulnerability
## window stops one impact from being applied twice in a row.
func _apply_impact_damage(amount: float, source: String) -> float:
	if _invulnerable > 0.0:
		return 0.0
	var applied := _damage(amount, source)
	if applied > 0.0:
		_invulnerable = IFRAME_SECONDS
		if player != null:
			player.shake(clampf(0.10 + applied * 0.02, 0.0, VoxelPlayer.SHAKE_MAX))
	return applied


func _on_landed(fall_distance: float) -> void:
	if state != State.PLAYING:
		return
	var damage := Survival.fall_damage(fall_distance)
	if damage > 0.0:
		_apply_impact_damage(damage, "fall")


func _on_health_changed() -> void:
	if hud != null and health != null:
		hud.set_health(health.health, health.max_health)


func _on_health_damaged(_amount: float, source: String) -> void:
	_last_damage_source = source


func _on_health_died() -> void:
	_enter_dead()


## The player is dead: freeze the body, show the death screen and wait there
## until the on-screen Respawn button is pressed.
func _enter_dead() -> void:
	if state == State.DEAD:
		return
	if crafting != null and crafting.is_open():
		crafting.close()
	state = State.DEAD
	player.velocity = Vector3.ZERO
	player.can_interact = false
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if death_screen != null:
		death_screen.show_death(_last_damage_source)
	print("M17_GAME_DEATH cause=%s" % _last_damage_source)


## Restores health/breath and returns the player to a valid spawn column.
func _respawn() -> void:
	if health == null:
		return
	health.revive()
	breath = Survival.MAX_BREATH
	_invulnerable = 0.0
	_seconds_since_damage = 0.0
	_last_damage_source = ""
	if death_screen != null:
		death_screen.hide_death()
	var spawn_column := _find_spawn_column()
	player.spawn_on_column(spawn_column.x, spawn_column.y)
	player.look_yaw(38.0)
	player.look_pitch(-12.0)
	player.can_interact = true
	player.set_physics_process(true)
	streamer.focus_at(player.global_position)
	state = State.PLAYING
	if not bool(_options["capture"]):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.flash("Respawned", 2.0)
	print("M17_GAME_RESPAWN player=%s" % player.global_position)


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
	hud.set_debug("%s\nXYZ %.1f / %.1f / %.1f   %s   %s   %s %s\nchunks %d/%d queued %d  ·  fluid queue %d  ·  %d fps%s" % [
		target_text,
		eye.x, eye.y, eye.z,
		_center_biome_name(),
		"flying" if player.flying else ("submerged" if player.is_submerged() else "walking"),
		clock.clock_text(), clock.phase_name(),
		streamer.loaded_count(), streamer.wanted_count(), streamer.queued_count(),
		fluid.pending_count() if fluid != null else 0,
		int(round(_last_fps)),
		"\nHUD hidden (F3 shows it)" if not hud.debug_visible() else "",
	])


func _center_biome_name() -> String:
	var cell := Vector3i(floori(player.global_position.x), floori(player.global_position.y), floori(player.global_position.z))
	return world.generator.biome_name(world.biome_at(cell.x, cell.z))


func _unhandled_input(event: InputEvent) -> void:
	if state == State.DEAD:
		# The death screen is modal: gameplay input and pause do nothing until
		# the on-screen Respawn button is pressed.
		return
	if event.is_action_pressed("release_mouse"):
		if state == State.PLAYING and crafting != null and crafting.is_open():
			# Escape closes the crafting panel before it would pause the game.
			_close_crafting()
		elif state == State.PLAYING:
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
		if event.is_action_pressed("open_crafting"):
			_toggle_crafting()
		elif crafting != null and crafting.is_open():
			# The open panel owns the mouse; ignore gameplay input.
			pass
		elif event.is_action_pressed("toggle_fly"):
			player.toggle_fly()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_handle_hotbar_input(event)


# =========================================================================
# Crafting
# =========================================================================

func _toggle_crafting() -> void:
	if crafting == null:
		return
	if crafting.is_open():
		_close_crafting()
	else:
		_open_crafting()


func _open_crafting() -> void:
	if crafting == null or state != State.PLAYING:
		return
	crafting.open()
	# While the panel is open the mouse drives the interface instead of the
	# world, so the player must not break or place blocks.
	player.can_interact = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_crafting() -> void:
	if crafting == null:
		return
	crafting.close()
	if state == State.PLAYING:
		player.can_interact = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_crafted(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		hud.flash("Crafted %d %s" % [
			int(result.get("output_count", 0)), BlockDB.name_of(int(result.get("output", BlockDB.AIR))),
		], 2.4)
	else:
		hud.flash(str(result.get("reason", "Cannot craft")), 2.4)
	hud.refresh()


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
	var written := saves.write(world, player, inventory, clock, health, breath)
	if written:
		hud.flash("Saved %d block edits to %s" % [world.edits.size(), ProjectSettings.globalize_path(saves.save_path())], 4.0)
		print("M17_GAME_SAVED path=%s block_edits=%d fluid_edits=%d" % [
			ProjectSettings.globalize_path(saves.save_path()), world.edits.size(), world.fluid_overrides.size(),
		])
	else:
		hud.flash("Save failed: %s" % saves.last_error, 5.0)
		push_error("M17_GAME_SAVE_FAILED %s" % saves.last_error)


func _save_silently(reason: String) -> void:
	if saves.write(world, player, inventory, clock, health, breath):
		print("M17_GAME_AUTOSAVE reason=%s block_edits=%d" % [reason, world.edits.size()])
	else:
		push_error("M17_GAME_AUTOSAVE_FAILED %s" % saves.last_error)


func _reload_now() -> void:
	var result := saves.read()
	if not result["ok"]:
		hud.flash("Load failed: %s" % result["error"], 5.0)
		return
	var applied: Dictionary = saves.apply(result["data"], world, player, inventory, clock, health)
	if not applied["ok"]:
		hud.flash("Load failed: %s" % applied["error"], 5.0)
		return
	if float(applied["breath"]) >= 0.0:
		breath = float(applied["breath"])
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
		"clock": clock.to_dictionary() if clock != null else {},
		"clock_text": clock.clock_text() if clock != null else "",
		"phase": clock.phase_name() if clock != null else "",
		"fluid": fluid.stats() if fluid != null else {},
		"mesher": mesher.stats,
		"edits": world.edits.size() if world != null else -1,
		"inventory_used_slots": inventory.used_slots(),
		"health": health.to_dictionary() if health != null else {},
		"breath": breath,
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
