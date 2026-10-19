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
var inventory_panel: InventoryPanel

# --- settlements and residents -------------------------------------------
const NpcModel = preload("res://scripts/core/npc.gd")
const NpcNodeScript = preload("res://scripts/game/npc_node.gd")
const SettlementModel = preload("res://scripts/core/settlement.gd")
const RaidModel = preload("res://scripts/core/raid.gd")

## Resident state by npc id, kept across sessions and across node retirement.
var npc_states: Dictionary = {}
## Shared settlement stores: settlement id -> { item_id: count }.
var settlement_stores: Dictionary = {}
## Live scene nodes by npc id.
var npc_nodes: Dictionary = {}
var settlements: Array = []
var npc_root: Node3D
var _settlement_timer := 0.0
## Settlement names by id (kept so a loaded resident can still say where it lives).
var _settlement_names: Dictionary = {}
## Tonight's raiders by id, the settlement under attack, and the last day that
## already had its raid, so a save never repeats one.
var raid_nodes: Dictionary = {}
var _raid_settlement := ""
var _raid_report_timer := 0.0
var _raided_day := -1
var settings_panel: SettingsPanelNode
var death_screen: DeathScreen
var saves: SaveManager
var health: Health
var settings: GameSettingsModel
var creature_model
var creature_nodes: Dictionary = {}
var creature_root: Node3D
var _creature_spawn_timer := 0.0
var hostile_model
var hostile_nodes: Dictionary = {}
var hostile_root: Node3D
var _hostile_spawn_timer := 0.0
const CreatureNode = preload("res://scripts/game/passive_creature.gd")
const CreatureModel = preload("res://scripts/core/passive_creatures.gd")
const HostileNode = preload("res://scripts/game/hostile_creature.gd")
const HostileModel = preload("res://scripts/core/hostile_creatures.gd")
const SettingsPanelNode = preload("res://scripts/game/settings_panel.gd")
const GameSettingsModel = preload("res://scripts/core/game_settings.gd")
const SETTINGS_PATH := "user://voxelworld_settings.cfg"

## Seconds of breath left; drained while the player's head is under water.
var breath := Survival.MAX_BREATH
## Hunger: 0..Survival.MAX_HUNGER, plus the accumulating exhaustion that costs a
## point of it.  Saved with the world (VERSION 4).
var hunger := Survival.MAX_HUNGER
var exhaustion := 0.0

var sun: DirectionalLight3D
var environment_node: WorldEnvironment
var environment: Environment
var sky_material: ShaderMaterial

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
	"fog_density": 0.0012,
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
	"open_inventory": false,
	"open_settings": false,
	"creature_feedback_capture": false,
	"spawn_hostiles": false,
	"hostile_feedback_capture": false,
	"sun_angle": Vector2(-48.0, -132.0),
	"shots": [],
	"shot_prefix": "",
	"quit_after": 0.0,
	"quit_after_settle": false,
	"health": -1.0,
	"hurt": -1.0,
	"submerge": false,
	"visual_test": "",
}

## Set when `--time-rate=` appears on the command line, so the capture harness
## only freezes the clock when the caller did not ask for a specific rate.
var _time_rate_given := false
## Set when `--render-distance=` appears, so the CLI value wins over a saved one.
var _render_distance_given := false
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
	_load_settings()
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
	player.mouse_sensitivity = settings.mouse_sensitivity
	_apply_display_settings()

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
	var sky_shader: Shader = load("res://shaders/sky.gdshader")
	sky_material = ShaderMaterial.new()
	sky_material.shader = sky_shader
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_energy_multiplier = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = clock.ambient_color()
	environment.ambient_light_sky_contribution = clock.ambient_sky_contribution()
	environment.ambient_light_energy = clock.ambient_energy()
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.0
	environment.adjustment_contrast = 1.04
	environment.adjustment_brightness = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = clock.fog_color()
	# A gentle exponential haze with sun scatter: enough to give distance and
	# soften the loaded-world edge without washing out the palette. `--fog=0`
	# disables it for comparison captures; `--fog=<density>` retunes it.
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = float(_options["fog_density"])
	environment.fog_sky_affect = 0.45
	environment.fog_sun_scatter = 0.22
	environment.fog_aerial_perspective = 0.35
	environment.ssao_enabled = true
	environment.ssao_radius = 0.8
	environment.ssao_intensity = 0.5
	environment.ssao_power = 1.4
	environment.ssao_detail = 0.5
	environment_node.environment = environment
	add_child(environment_node)
	_update_sky()

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	_set_sun_angles(float(_options["sun_angle"].x), float(_options["sun_angle"].y))
	sun.light_color = clock.sun_color()
	sun.light_energy = clock.sun_energy()
	sun.shadow_enabled = bool(_options["shadows"])
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = float(_options["shadow_distance"])
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.025
	sun.shadow_normal_bias = 1.4
	sun.shadow_opacity = 0.88
	sun.light_angular_distance = 1.0
	sun.light_specular = 0.35
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
		sky_material.set_shader_parameter("sky_top", clock.sky_top_color())
		sky_material.set_shader_parameter("sky_horizon", clock.sky_horizon_color())
		sky_material.set_shader_parameter("ground_bottom", clock.ground_bottom_color())
		sky_material.set_shader_parameter("ground_horizon", clock.ground_horizon_color())
		sky_material.set_shader_parameter("sunset_color", clock.sunset_color())
		sky_material.set_shader_parameter("sunset_amount", clock.sunset_amount())
		sky_material.set_shader_parameter("day_amount", clock.daylight())
		sky_material.set_shader_parameter("star_amount", clock.star_amount())
		sky_material.set_shader_parameter("cloud_amount", clock.cloud_amount())
	var water := materials.water_material()
	if water != null:
		water.set_shader_parameter("water_tint", clock.water_tint())


func _set_sun_angles(pitch: float, yaw: float) -> void:
	sun.rotation_degrees = Vector3(pitch, yaw, 0.0)


func _build_nodes() -> void:
	player = VoxelPlayer.new()
	player.name = "Player"
	player.show_target_marker = str(_options["visual_test"]).is_empty()
	player.gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	player.can_interact = false
	player.set_physics_process(false)
	player.set_process(false)
	add_child(player)

	streamer = ChunkStreamer.new()
	streamer.name = "ChunkStreamer"
	streamer.render_radius = settings.render_distance
	streamer.vertical_radius = int(_options["vertical_radius"])
	streamer.generation_budget = int(_options["generation_budget"])
	streamer.generation_millisecond_budget = float(_options["generation_budget_ms"])
	streamer.mesh_budget = int(_options["mesh_budget"])
	streamer.mesh_millisecond_budget = float(_options["mesh_budget_ms"])
	streamer.focus_node = player
	add_child(streamer)

	npc_root = Node3D.new()
	npc_root.name = "Residents"
	add_child(npc_root)

	player.block_broken.connect(_on_block_broken)
	player.block_placed.connect(_on_block_placed)
	player.target_changed.connect(_on_target_changed)
	player.interaction_failed.connect(_on_interaction_failed)
	player.fly_changed.connect(_on_fly_changed)
	player.landed.connect(_on_landed)
	player.creature_attacked.connect(_on_creature_attacked)
	player.harvest_failed.connect(_on_harvest_failed)
	player.tool_broken.connect(_on_tool_broken)
	player.eat_requested.connect(_on_eat_requested)


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
	crafting.setup(inventory, library)
	crafting.crafted.connect(_on_crafted)

	# The settings panel shares the crafting layer height, just above it, so both
	# overlays draw over the HUD but the death screen and menu still cover them.
	var settings_layer := CanvasLayer.new()
	settings_layer.name = "SettingsLayer"
	settings_layer.layer = 16
	add_child(settings_layer)
	settings_panel = SettingsPanelNode.new()
	settings_panel.name = "SettingsPanel"
	settings_layer.add_child(settings_panel)
	settings_panel.setup(settings)
	settings_panel.setting_changed.connect(_on_setting_changed)

	# The inventory interface shares the crafting layer height: only one of the
	# three panels is ever open, and they close each other.
	inventory_panel = InventoryPanel.new()
	inventory_panel.name = "InventoryPanel"
	crafting_layer.add_child(inventory_panel)
	inventory_panel.setup(inventory, library)

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
				_render_distance_given = true
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
			"--shot-prefix":
				# Names a tour's frames `<prefix>-0.png`, `<prefix>-1.png`, ...
				# so a sweep does not overwrite unrelated tracked captures.
				_options["shot_prefix"] = value
			"--straight-to-game":
				_options["straight_to_game"] = true
			"--open-crafting":
				_options["open_crafting"] = true
			"--open-inventory":
				_options["open_inventory"] = true
			"--find-structure":
				# Diagnostic: teleport to the nearest placed structure (optionally of
				# a given id) so a capture can show one without a long walk.
				_options["find_structure"] = value if not value.is_empty() else "any"
			"--follow-resident":
				# Diagnostic: keep the capture camera on the nearest resident, so a
				# screenshot shows somebody actually working.
				_options["follow_resident"] = true
			"--raid-now":
				# Diagnostic: force tonight's raid to start immediately, so a
				# capture or a manual check does not have to wait for nightfall.
				_options["raid_now"] = true
			"--open-settings":
				_options["open_settings"] = true
			"--tools":
				# Diagnostic: one tool of each tier plus materials and food, so a
				# capture can show the item icons, durability bars and the HUD
				# without a scripted mining session.
				_options["tools"] = true
			"--hunger":
				# Diagnostic: start with a specific hunger value so a capture can
				# show a partly empty hunger bar.
				_options["hunger"] = clampf(value.to_float(), 0.0, Survival.MAX_HUNGER)
			"--creature-feedback-capture":
				_options["creature_feedback_capture"] = true
			"--spawn-hostiles":
				_options["spawn_hostiles"] = true
			"--hostile-feedback-capture":
				_options["hostile_feedback_capture"] = true
				_options["spawn_hostiles"] = true
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
			"--visual-test":
				# M18 reproducible visual test area (see VisualTestArena).  The
				# optional value selects the fixed viewpoint: close, normal, wide.
				_options["visual_test"] = value if not value.is_empty() else "normal"


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
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
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
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
	state = State.LOADING
	_loading_seconds = 0.0
	_play_seconds = 0.0
	_autosave_timer = 0.0
	_stream_report_printed = false
	clock = DayNight.new(float(_options["time_of_day"]), _cycle_length())
	_update_sky()
	health.revive()
	breath = Survival.MAX_BREATH
	hunger = Survival.MAX_HUNGER
	exhaustion = 0.0
	_invulnerable = 0.0
	_seconds_since_damage = 0.0
	_last_damage_source = ""

	world = VoxelWorld.new(seed_value)
	creature_model = CreatureModel.new(seed_value)
	creature_nodes.clear()
	_creature_spawn_timer = 0.0
	if is_instance_valid(creature_root):
		creature_root.queue_free()
	creature_root = Node3D.new()
	creature_root.name = "PassiveCreatures"
	add_child(creature_root)
	hostile_model = HostileModel.new(seed_value)
	hostile_nodes.clear()
	_hostile_spawn_timer = 0.0
	if is_instance_valid(hostile_root):
		hostile_root.queue_free()
	hostile_root = Node3D.new()
	hostile_root.name = "HostileCreatures"
	add_child(hostile_root)
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
	if bool(_options.get("tools", false)):
		_give_diagnostic_tools()
	if _options.has("hunger"):
		hunger = float(_options["hunger"])

	var spawn_column := _find_spawn_column()
	if not str(_options["visual_test"]).is_empty():
		# Load the showcase site first; the arena is built once the area is ready.
		spawn_column = Vector2i(VisualTestArena.CENTER.x, VisualTestArena.CENTER.z)
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
			if float(applied.get("hunger", -1.0)) >= 0.0:
				hunger = float(applied["hunger"])
			_apply_npcs(applied.get("npcs", {}))
			streamer.focus_at(player.global_position)
			hud.flash("Loaded %d block edits and %d fluid changes" % [int(applied["block_edits"]), int(applied["fluid_edits"])], 5.0)
	hud.set_hunger(hunger, Survival.MAX_HUNGER)
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


## Diagnostic loadout for captures and manual checks (`--tools`): one tool per
## tier (each part-worn, so the durability bars show), a build material, the
## crafting materials and food, in exactly the nine hotbar slots so the capture is
## deterministic.
func _give_diagnostic_tools() -> void:
	for index in Inventory.HOTBAR_SIZE:
		inventory.clear_slot(index)
	inventory.add(ItemDB.WOOD_PICKAXE, 1, 20)
	inventory.add(ItemDB.STONE_AXE, 1, 60)
	inventory.add(ItemDB.IRON_SHOVEL, 1, 150)
	inventory.add(ItemDB.DIAMOND_SWORD, 1, ItemDB.max_durability(ItemDB.DIAMOND_SWORD))
	inventory.add(BlockDB.COBBLESTONE, 32)
	inventory.add(ItemDB.STICK, 32)
	inventory.add(ItemDB.IRON_INGOT, 4)
	inventory.add(ItemDB.COAL, 8)
	inventory.add(ItemDB.APPLE, 6)


## Diagnostic (`--find-structure`): places the player above the nearest structure
## so a capture or a manual check can inspect one without a long walk.
func _apply_find_structure() -> void:
	var wanted := str(_options.get("find_structure", ""))
	if wanted.is_empty() or world == null or player == null:
		return
	var placement := _nearest_structure(wanted)
	if placement.is_empty():
		hud.flash("No '%s' structure within 6 regions" % wanted, 5.0)
		return
	var definition := StructureDB.definition(str(placement["id"]))
	var size := StructureDB.footprint(definition)
	var origin_x := int(placement["x"]) - (size.x - 1) / 2
	var origin_z := int(placement["z"]) - (size.z - 1) / 2
	# A high, slightly behind view: close enough that a settlement's residents are
	# visible, high enough to see over the trees around it.
	player.flying = true
	player.teleport_to(Vector3(origin_x + size.x * 0.5, float(placement["base_y"]) + 9.0, origin_z - 12.0))
	player.look_yaw(180.0)
	player.look_pitch(-28.0)
	streamer.focus_at(player.global_position)
	hud.flash("Found %s at (%d, %d, %d)" % [definition["name"], int(placement["x"]),
		int(placement["base_y"]), int(placement["z"])], 8.0)
	print("M17_STRUCTURE_FOUND id=%s x=%d y=%d z=%d biome=%d" % [placement["id"], int(placement["x"]),
		int(placement["base_y"]), int(placement["z"]), int(placement["biome"])])


## Fixed viewpoints for the M18 visual test area.  They are absolute so the same
## `--visual-test` run always produces a comparable capture.
func _apply_visual_test_view(mode: String) -> void:
	var centre := VisualTestArena.CENTER
	var feet := float(VisualTestArena.BASE_Y) + 1.05
	match mode:
		"close":
			player.teleport_to(Vector3(centre.x + 0.5, feet, centre.z + 4.0))
			player.look_yaw(0.0)
			player.look_pitch(-12.0)
		"wide":
			player.flying = true
			player.teleport_to(Vector3(centre.x + 0.5, 90.0, centre.z + 20.0))
			player.look_yaw(0.0)
			player.look_pitch(-38.0)
		"shore":
			# East of the pond, raised slightly, looking back across the water and
			# the plaza so the shoreline and the water surface are both readable.
			player.flying = true
			player.teleport_to(Vector3(centre.x + 10.5, float(VisualTestArena.BASE_Y) + 3.5, centre.z + 2.0))
			player.look_yaw(100.0)
			player.look_pitch(-18.0)
		"sky":
			player.flying = true
			player.teleport_to(Vector3(centre.x + 0.5, float(VisualTestArena.BASE_Y) + 7.0, centre.z + 8.0))
			player.look_yaw(0.0)
			player.look_pitch(32.0)
		_:
			player.teleport_to(Vector3(centre.x + 0.5, feet, centre.z + 8.0))
			player.look_yaw(0.0)
			player.look_pitch(-6.0)
	streamer.focus_at(player.global_position)


## The nearest placement matching `wanted` ("any" or a structure id), searched in
## expanding rings of regions around the origin.
func _nearest_structure(wanted: String) -> Dictionary:
	for ring in range(0, 7):
		var best := {}
		var best_distance := 1 << 30
		for region_z in range(-ring, ring + 1):
			for region_x in range(-ring, ring + 1):
				if maxi(absi(region_x), absi(region_z)) != ring:
					continue
				var placement := world.generator.structure_placement(Vector2i(region_x, region_z))
				if placement.is_empty():
					continue
				if wanted != "any" and str(placement["id"]) != wanted:
					continue
				var x := int(placement["x"])
				var z := int(placement["z"])
				var distance := x * x + z * z
				if distance < best_distance:
					best_distance = distance
					best = placement
		if not best.is_empty():
			return best
	return {}


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
	if not str(_options["visual_test"]).is_empty():
		VisualTestArena.new().build(world)
	_apply_override_position()
	if not str(_options["visual_test"]).is_empty() and not (_options["player_at"] as Vector3).is_finite():
		_apply_visual_test_view(str(_options["visual_test"]))
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
	if bool(_options["open_inventory"]):
		_open_inventory()
	if bool(_options["open_settings"]):
		_open_settings()
	_apply_find_structure()
	print("M17_GAME_READY seed=%d player=%s chunks=%d views=%d meshed=%d" % [
		world.world_seed, player.global_position, streamer.loaded_count(), streamer.view_count(), int(streamer.stats["meshed"]),
	])
	_apply_health_option()
	_apply_hurt_option()
	if bool(_options["creature_feedback_capture"]):
		_spawn_creature_feedback_capture()
	if bool(_options["hostile_feedback_capture"]):
		_spawn_hostile_feedback_capture()


## Reproducible capture aid: place one legal boar in front of the player and
## show the same hurt feedback produced by a real player attack.
func _spawn_creature_feedback_capture() -> void:
	for creature: Node in creature_nodes.values():
		if is_instance_valid(creature):
			creature.queue_free()
	creature_nodes.clear()
	creature_model.states.clear()
	var chosen := Vector3i.ZERO
	var found := false
	var offsets := [0, -1, 1, -2, 2, -3, 3, -4, 4]
	for distance in range(4, 9):
		for offset: int in offsets:
			var x := floori(player.global_position.x) + offset
			var z := floori(player.global_position.z) - distance
			var height := world.generator.height_at(x, z)
			var foot := Vector3i(x, height + 1, z)
			var head := foot + Vector3i(0, 1, 0)
			if height <= WorldGen.SEA_LEVEL or not world.is_loaded(foot) or not world.is_loaded(head):
				continue
			if world.get_block(foot) == BlockDB.AIR and world.get_block(head) == BlockDB.AIR:
				chosen = foot
				found = true
				break
		if found:
			break
	if not found:
		return
	var creature_state := {"id": 900001, "species": "boar", "key": "capture-boar",
		"position": Vector3(chosen) + Vector3(0.5, 0.0, 0.5), "health": CreatureModel.HIT_POINTS,
		"alive": true, "wander": Vector3.ZERO}
	creature_model.states["capture-boar"] = creature_state.duplicate(true)
	var creature = CreatureNode.new()
	creature.configure(creature_state, world)
	creature_root.add_child(creature)
	creature.set_physics_process(false)
	creature.rotation.y = PI
	creature_nodes[str(creature_state.key)] = creature
	creature.killed.connect(_on_creature_killed)
	player.look_yaw(0.0)
	player.look_pitch(-12.0)
	_on_creature_attacked(creature)
	hud.flash("Boar hurt (%d/%d)" % [CreatureModel.HIT_POINTS - 1, CreatureModel.HIT_POINTS], 30.0)


## Reproducible capture aid: place one hostile grunt in front of the player,
## hold it still and show the same hurt feedback a real player hit produces.
func _spawn_hostile_feedback_capture() -> void:
	for hostile: Node in hostile_nodes.values():
		if is_instance_valid(hostile):
			hostile.queue_free()
	hostile_nodes.clear()
	hostile_model.states.clear()
	var chosen := Vector3i.ZERO
	var found := false
	var offsets := [0, -1, 1, -2, 2, -3, 3, -4, 4]
	for distance in range(4, 9):
		for offset: int in offsets:
			var x := floori(player.global_position.x) + offset
			var z := floori(player.global_position.z) - distance
			var height := world.generator.height_at(x, z)
			var foot := Vector3i(x, height + 1, z)
			var head := foot + Vector3i(0, 1, 0)
			if height <= WorldGen.SEA_LEVEL or not world.is_loaded(foot) or not world.is_loaded(head):
				continue
			if world.get_block(foot) == BlockDB.AIR and world.get_block(head) == BlockDB.AIR:
				chosen = foot
				found = true
				break
		if found:
			break
	if not found:
		return
	var hostile_state := {"id": 900002, "species": "grunt", "key": "capture-grunt",
		"position": Vector3(chosen) + Vector3(0.5, 0.0, 0.5), "health": HostileModel.HIT_POINTS,
		"alive": true}
	hostile_model.states["capture-grunt"] = hostile_state.duplicate(true)
	var hostile = HostileNode.new()
	hostile.configure(hostile_state, world, player)
	hostile_root.add_child(hostile)
	hostile.set_physics_process(false)
	hostile.rotation.y = PI
	hostile_nodes[str(hostile_state.key)] = hostile
	hostile.killed.connect(_on_hostile_killed)
	player.look_yaw(0.0)
	player.look_pitch(-12.0)
	_on_creature_attacked(hostile)
	hud.flash("Grunt hurt (%d/%d)" % [HostileModel.HIT_POINTS - 1, HostileModel.HIT_POINTS], 30.0)


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
	if settings_panel != null and settings_panel.is_open():
		settings_panel.close()
	if crafting != null and crafting.is_open():
		crafting.close()
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
	state = State.PAUSED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.can_interact = false
	player.velocity = Vector3.ZERO
	# Freeze the body: the physics loop keeps reading WASD while the menu is up,
	# so without this the player keeps moving (and falling) behind the pause menu.
	player.set_physics_process(false)
	menu.set_save_callback(_save_now)
	menu.set_title_callback(_return_to_title)
	menu.show_pause()


func _resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	player.can_interact = true
	player.set_physics_process(true)
	menu.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _return_to_title() -> void:
	_save_now()
	streamer.clear()
	if is_instance_valid(creature_root):
		creature_root.queue_free()
		creature_root = null
	creature_nodes.clear()
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
			# The visual test area is a still-life render target.  Keep transient
			# creatures, residents and raids out of it so captures are stable and
			# comparable; normal play still runs all of them.
			if str(_options["visual_test"]).is_empty():
				_update_creatures(delta)
				_update_hostiles(delta)
				_update_npcs(delta)
				_update_raid(delta)
			_update_status()
			if hud != null and player != null:
				hud.set_mining_progress(player.mining_ratio())
			if not bool(_options["capture"]) and str(_options["visual_test"]).is_empty() and _autosave_timer >= AUTOSAVE_SECONDS:
				_autosave_timer = 0.0
				_save_silently("autosave")
		_:
			pass
	# The capture harness also has to run on the death screen, so it is driven
	# from every "world is up" state rather than from the playing branch.
	if bool(_options["capture"]) and state in [State.PLAYING, State.DEAD]:
		if bool(_options.get("follow_resident", false)) and state == State.PLAYING:
			_follow_nearest_resident()
		_update_capture(delta)


## Per-frame survival: drowning while submerged, hunger from what the player is
## doing, starvation damage at zero hunger, and fed regeneration.  Falls are
## event-driven (`player.landed`).
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

	# Hunger: movement and jumping build exhaustion; every full budget costs a
	# point and an empty bar starves the body down to its health floor.
	var hunger_step: Dictionary = Survival.hunger_step(hunger, exhaustion, _activity_exhaustion(), delta)
	hunger = hunger_step["hunger"]
	exhaustion = hunger_step["exhaustion"]
	var starve := Survival.starvation_damage(hunger, health.health, delta)
	if starve > 0.0:
		_damage(starve, "starvation")

	var regen: Dictionary = Survival.regen_step(health.health, health.max_health,
		_seconds_since_damage, delta, hunger, exhaustion)
	exhaustion = regen["exhaustion"]
	if float(regen["healed"]) > 0.0:
		health.heal(float(regen["healed"]))
	hud.set_breath(breath, Survival.MAX_BREATH, submerged or breath < Survival.MAX_BREATH - 0.001)
	hud.set_hunger(hunger, Survival.MAX_HUNGER)


## Exhaustion per second for what the player is doing right now.
func _activity_exhaustion() -> float:
	if player == null:
		return float(Survival.ACTIVITY_EXHAUSTION["idle"])
	if player.flying:
		return float(Survival.ACTIVITY_EXHAUSTION["idle"])
	var horizontal := Vector2(player.velocity.x, player.velocity.z).length()
	if horizontal < 0.3:
		return float(Survival.ACTIVITY_EXHAUSTION["idle"])
	if horizontal >= player.move_speed * 1.2:
		return float(Survival.ACTIVITY_EXHAUSTION["sprint"])
	return float(Survival.ACTIVITY_EXHAUSTION["walk"])


## Right-click with food in hand.  A full body refuses (so the item is not
## destroyed for nothing); otherwise the food fills hunger and may heal.
func _on_eat_requested(item_id: int) -> void:
	if inventory == null:
		return
	var effect: Dictionary = Survival.food_effect(hunger, ItemDB.food_value(item_id), ItemDB.heal_value(item_id))
	if not bool(effect["improved"]):
		hud.flash("%s would be wasted — you are not hungry" % ItemDB.name_of(item_id), 1.6)
		return
	hunger = effect["hunger"]
	exhaustion = maxf(0.0, exhaustion - Survival.EXHAUSTION_PER_HUNGER)
	var healed := 0.0
	if float(effect["heal"]) > 0.0 and health != null:
		healed = health.heal(float(effect["heal"]))
	inventory.take_from_slot(inventory.selected)
	hud.set_hunger(hunger, Survival.MAX_HUNGER)
	hud.flash("Ate %s%s" % [ItemDB.name_of(item_id),
		"" if healed <= 0.0 else "  +%d health" % int(round(healed))], 1.8)
	hud.refresh()


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
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
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
	hunger = Survival.MAX_HUNGER
	exhaustion = 0.0
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
	# A resident under the crosshair describes itself (name, role, what it is
	# doing) on its own line.
	var resident := _npc_target_text()
	if not resident.is_empty():
		target_text += "\n%s" % resident
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
		if state == State.PLAYING and inventory_panel != null and inventory_panel.is_open():
			# Escape closes the inventory before it would pause the game.
			_close_inventory()
		elif state == State.PLAYING and settings_panel != null and settings_panel.is_open():
			# Escape closes the settings panel before it would pause the game.
			_close_settings()
		elif state == State.PLAYING and crafting != null and crafting.is_open():
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
		if event.is_action_pressed("open_settings"):
			_toggle_settings()
		elif event.is_action_pressed("open_crafting"):
			_toggle_crafting()
		elif event.is_action_pressed("open_inventory"):
			_toggle_inventory()
		elif (settings_panel != null and settings_panel.is_open()) \
				or (crafting != null and crafting.is_open()) \
				or (inventory_panel != null and inventory_panel.is_open()):
			# The open overlay owns the mouse; ignore gameplay input.
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
	if settings_panel != null and settings_panel.is_open():
		settings_panel.close()
	# Which stations the player can use right now: any crafting table (or
	# furnace) block that is loaded within a few blocks of the player.
	crafting.set_station(_current_station())
	crafting.open()
	# While the panel is open the mouse drives the interface instead of the
	# world, so the player must not break or place blocks.
	player.can_interact = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The best crafting station in the player's surroundings.  Deliberately a small
## radius: the station is a place in the world, not a menu toggle.
func _current_station() -> String:
	if world == null or player == null:
		return Crafting.STATION_HAND
	var feet := Vector3i(
		floori(player.global_position.x),
		floori(player.global_position.y),
		floori(player.global_position.z))
	return Crafting.best_station(world, feet, 4)


func _close_crafting() -> void:
	if crafting == null:
		return
	crafting.close()
	if state == State.PLAYING:
		player.can_interact = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_crafted(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		var crafted_count := int(result.get("crafted", 1))
		var total := int(result.get("output_count", 0)) * crafted_count
		hud.flash("Crafted %d %s%s" % [
			total, ItemDB.name_of(int(result.get("output", BlockDB.AIR))),
			"" if crafted_count <= 1 else " (%d crafts)" % crafted_count,
		], 2.4)
	else:
		hud.flash(str(result.get("reason", "Cannot craft")), 2.4)
	# The station can change while the panel is open (the player cannot move, but
	# a robot/paste could), and the affordability of every row just changed.
	if crafting != null and crafting.is_open():
		crafting.set_station(_current_station())
	hud.refresh()


# =========================================================================
# Settings
# =========================================================================

func _toggle_settings() -> void:
	if settings_panel == null:
		return
	if settings_panel.is_open():
		_close_settings()
	else:
		_open_settings()


# =========================================================================
# Inventory interface
# =========================================================================

func _toggle_inventory() -> void:
	if inventory_panel == null:
		return
	if inventory_panel.is_open():
		_close_inventory()
	else:
		_open_inventory()


func _open_inventory() -> void:
	if inventory_panel == null or state != State.PLAYING:
		return
	# The three overlays are mutually exclusive: opening one closes the others.
	if crafting != null and crafting.is_open():
		crafting.close()
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
	if settings_panel != null and settings_panel.is_open():
		settings_panel.close()
	inventory_panel.open()
	player.can_interact = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_inventory() -> void:
	if inventory_panel == null:
		return
	inventory_panel.close()
	if state == State.PLAYING:
		player.can_interact = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	if settings_panel == null or state != State.PLAYING:
		return
	if crafting != null and crafting.is_open():
		crafting.close()
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
	settings_panel.open()
	player.can_interact = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_settings() -> void:
	if settings_panel == null:
		return
	settings_panel.close()
	if state == State.PLAYING:
		player.can_interact = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Applies one changed setting to the live game and persists the whole set.
func _on_setting_changed(key: String, value: Variant) -> void:
	if settings == null:
		return
	match key:
		"render_distance":
			settings.set_render_distance(float(value))
			if streamer != null:
				streamer.apply_render_radius(settings.render_distance)
		"mouse_sensitivity":
			settings.set_mouse_sensitivity(float(value))
			if player != null:
				player.mouse_sensitivity = settings.mouse_sensitivity
		"vsync":
			settings.set_vsync(bool(value))
			_apply_display_settings()
	_save_settings()


func _apply_display_settings() -> void:
	if settings == null:
		return
	var mode := DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


func _load_settings() -> void:
	settings = GameSettingsModel.new()
	settings.set_render_distance(float(_options["render_radius"]))
	if FileAccess.file_exists(SETTINGS_PATH):
		var config := ConfigFile.new()
		if config.load(SETTINGS_PATH) == OK:
			settings.from_dictionary({
				"render_distance": config.get_value("game", "render_distance", settings.render_distance),
				"mouse_sensitivity": config.get_value("game", "mouse_sensitivity", settings.mouse_sensitivity),
				"vsync": config.get_value("game", "vsync", settings.vsync),
			})
	# A command-line render distance is explicit intent for this run (captures,
	# profiling) and wins over the saved value.
	if _render_distance_given:
		settings.set_render_distance(float(_options["render_radius"]))


func _save_settings() -> void:
	if settings == null:
		return
	var config := ConfigFile.new()
	var values: Dictionary = settings.to_dictionary()
	config.set_value("game", "render_distance", values["render_distance"])
	config.set_value("game", "mouse_sensitivity", values["mouse_sensitivity"])
	config.set_value("game", "vsync", values["vsync"])
	config.save(SETTINGS_PATH)


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
		collected = "  +1 %s" % ItemDB.name_of(drop) if leftover == 0 else "  (inventory full)"
	hud.flash("Mined %s at (%d, %d, %d)%s" % [BlockDB.name_of(block_id), world_position.x, world_position.y, world_position.z, collected], 1.6)


func _on_block_placed(world_position: Vector3i, block_id: int) -> void:
	inventory.take_from_slot(inventory.selected)
	hud.flash("Placed %s at (%d, %d, %d)" % [BlockDB.name_of(block_id), world_position.x, world_position.y, world_position.z], 1.4)


func _update_creatures(delta: float) -> void:
	if creature_model == null or creature_root == null:
		return
	_creature_spawn_timer -= delta
	if _creature_spawn_timer <= 0.0:
		_creature_spawn_timer = 1.0
		var focus := Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
		var remaining: int = CreatureModel.CAP - creature_nodes.size()
		if remaining > 0:
			for state: Dictionary in creature_model.spawn_candidates(focus, world, remaining):
				var creature = CreatureNode.new()
				creature.configure(state, world)
				creature_root.add_child(creature)
				creature_nodes[str(state.key)] = creature
				creature.killed.connect(_on_creature_killed)
	for key: Variant in creature_nodes.keys():
		var living: Node = creature_nodes[key]
		if is_instance_valid(living) and bool(living.state.get("alive", false)):
			var updated: Dictionary = creature_model.states.get(str(key), {}).duplicate(true)
			updated["position"] = living.global_position
			creature_model.states[str(key)] = updated
	var player_flat := Vector3(player.global_position.x, 0.0, player.global_position.z)
	for key: Variant in creature_model.prune(player_flat, 4):
		var creature: Node = creature_nodes.get(str(key))
		if creature != null:
			creature_nodes.erase(str(key))
			creature.queue_free()


func _on_creature_attacked(creature, damage: int = 1) -> void:
	if not is_instance_valid(creature):
		return
	if creature.is_in_group("npc"):
		if creature.apply_hit(damage):
			creature.die()
		else:
			hud.flash("%s is hurt (%d/%d)" % [str(creature.state.get("name", "Resident")),
				int(creature.state["health"]), int(NpcModel.HEALTH)], 1.2)
		return
	if creature.is_in_group("hostile_creature"):
		var hostile_drops: int = creature.apply_hit(damage)
		if hostile_drops <= 0:
			hud.flash("Grunt hurt (%d/%d)" % [int(creature.state.health), HostileModel.HIT_POINTS], 1.0)
		return
	if not creature.is_in_group("passive_creature"):
		return
	var drops: int = creature.apply_hit(damage)
	if drops <= 0:
		hud.flash("Boar hurt (%d/%d)" % [int(creature.state.health), CreatureModel.HIT_POINTS], 1.0)


## The block broke, but its drop needed a tool class the player was not holding.
func _on_harvest_failed(block_id: int, required_tool: int) -> void:
	hud.flash("%s needs a %s to drop anything" % [
		BlockDB.name_of(block_id), ItemDB.tool_name(required_tool)], 1.8)


func _on_tool_broken(item_id: int) -> void:
	hud.flash("Your %s broke" % ItemDB.name_of(item_id), 2.2)
	hud.refresh()


func _on_creature_killed(creature, drop_count: int = 1) -> void:
	var leftover: int = inventory.add(CreatureModel.DROP_ID, drop_count)
	var key := str(creature.state.get("key", ""))
	creature_model.states.erase(key)
	creature_nodes.erase(key)
	creature.queue_free()
	hud.flash("Boar down  +%d Oak Log%s" % [drop_count - leftover, "" if leftover == 0 else " (inventory full)"], 2.0)
	hud.refresh()


## Hostiles are a night/darkness threat: they spawn while the clock says night
## (or when `--spawn-hostiles` forces them for a capture/integration run) and are
## cleared at dawn.  Like the passive boars their state is transient (never
## saved); on load the night spawner re-seeds a fresh population.
func _hostiles_active() -> bool:
	if bool(_options["spawn_hostiles"]):
		return true
	return clock != null and clock.is_night()


func _update_hostiles(delta: float) -> void:
	if hostile_model == null or hostile_root == null or player == null:
		return
	if not _hostiles_active():
		# Dawn: retire the night's population a few per frame so it never stalls.
		var retired := 0
		for key: Variant in hostile_nodes.keys():
			if retired >= 2:
				break
			var node: Node = hostile_nodes[key]
			hostile_nodes.erase(key)
			hostile_model.states.erase(str(key))
			if is_instance_valid(node):
				node.queue_free()
			retired += 1
		return
	_hostile_spawn_timer -= delta
	if _hostile_spawn_timer <= 0.0:
		_hostile_spawn_timer = 2.0
		var focus := Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
		var remaining: int = HostileModel.CAP - hostile_nodes.size()
		if remaining > 0:
			for state: Dictionary in hostile_model.spawn_candidates(focus, world, remaining, true):
				var hostile = HostileNode.new()
				hostile.configure(state, world, player)
				hostile_root.add_child(hostile)
				hostile_nodes[str(state.key)] = hostile
				hostile.killed.connect(_on_hostile_killed)
				hostile.attacked_player.connect(_on_hostile_attacked_player)
	for key: Variant in hostile_nodes.keys():
		var living: Node = hostile_nodes[key]
		if is_instance_valid(living) and bool(living.state.get("alive", false)):
			var updated: Dictionary = hostile_model.states.get(str(key), {}).duplicate(true)
			updated["position"] = living.global_position
			hostile_model.states[str(key)] = updated
	var player_flat := Vector3(player.global_position.x, 0.0, player.global_position.z)
	for key: Variant in hostile_model.prune(player_flat, 4):
		var hostile: Node = hostile_nodes.get(str(key))
		if hostile != null:
			hostile_nodes.erase(str(key))
			hostile.queue_free()


func _on_hostile_attacked_player(amount: float) -> void:
	if state != State.PLAYING:
		return
	_apply_impact_damage(amount, "grunt")


func _on_hostile_killed(creature, drop_count: int = 1) -> void:
	var leftover: int = inventory.add(HostileModel.DROP_ID, drop_count)
	var key := str(creature.state.get("key", ""))
	hostile_model.states.erase(key)
	hostile_nodes.erase(key)
	creature.queue_free()
	hud.flash("Grunt down  +%d %s%s" % [
		drop_count - leftover, ItemDB.name_of(HostileModel.DROP_ID),
		"" if leftover == 0 else " (inventory full)",
	], 2.0)
	hud.refresh()


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
	var written := saves.write(world, player, inventory, clock, health, breath, hunger, _npcs_to_dictionary())
	if written:
		hud.flash("Saved %d block edits to %s" % [world.edits.size(), ProjectSettings.globalize_path(saves.save_path())], 4.0)
		print("M17_GAME_SAVED path=%s block_edits=%d fluid_edits=%d" % [
			ProjectSettings.globalize_path(saves.save_path()), world.edits.size(), world.fluid_overrides.size(),
		])
	else:
		hud.flash("Save failed: %s" % saves.last_error, 5.0)
		push_error("M17_GAME_SAVE_FAILED %s" % saves.last_error)


func _save_silently(reason: String) -> void:
	if saves.write(world, player, inventory, clock, health, breath, hunger, _npcs_to_dictionary()):
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
	if float(applied.get("hunger", -1.0)) >= 0.0:
		hunger = float(applied["hunger"])
		exhaustion = 0.0
	_apply_npcs(applied.get("npcs", {}))
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
				if shots.is_empty():
					_report_and_quit()
					return
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
	var prefix := str(_options["shot_prefix"])
	if prefix.is_empty():
		prefix = "godot-game-tour"
	return "%s-%d.png" % [prefix, index]


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
		"mesher": streamer.mesher_stats() if streamer != null else mesher.stats,
		"edits": world.edits.size() if world != null else -1,
		"inventory_used_slots": inventory.used_slots(),
		"health": health.to_dictionary() if health != null else {},
		"breath": breath,
		"hunger": {"hunger": hunger, "exhaustion": exhaustion},
		"npcs": {"states": npc_states.size(), "nodes": npc_nodes.size(),
			"settlements": settlements.size(), "stored": settlement_stores.size()},
		"raid": {"day": clock.day_index if clock != null else -1, "active": raid_nodes.size(),
			"settlement": _raid_settlement, "last_day": _raided_day},
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
		"mesher": streamer.mesher_stats() if streamer != null else mesher.stats,
	}, "\t") + "\n")
	file.close()
	return path


# =========================================================================
# Settlements and residents
# =========================================================================

## Residents are derived from the settlements near the player (a settlement is a
## placed hut or campsite), stepped by the node-free model, and shown by one node
## each.  A settlement only "exists" while it is close, and only the settlements
## close enough to matter are tracked, so a distant village costs nothing.
func _update_npcs(delta: float) -> void:
	if world == null or player == null or npc_root == null:
		return
	_settlement_timer -= delta
	if _settlement_timer <= 0.0:
		_settlement_timer = 2.0
		_refresh_settlements()
	for id: Variant in npc_states.keys():
		var state: Dictionary = npc_states[id]
		if _npc_distance(state) > NpcModel.ACTIVE_RADIUS:
			continue
		_settle_npc_on_ground(state)
		var store: Dictionary = settlement_stores.get(str(state.get("settlement", "")), {})
		var events: Dictionary = NpcModel.step(state, world, store, delta, _raid_threats())
		_apply_npc_events(state, events)
	_sync_npc_nodes()


## The model moves a resident in x/z only; the game keeps its feet on the ground.
## A resident that has fallen (or been dug out from under) more than a few blocks
## away from its home level is sent home instead of wandering underground.
func _settle_npc_on_ground(state: Dictionary) -> void:
	var position: Vector3 = state["position"]
	var cell := Vector3i(floori(position.x), floori(position.y) - 1, floori(position.z))
	var ground := -2147483648
	for offset in range(-2, 6):
		var probe := cell + Vector3i(0, -offset, 0)
		if not world.is_loaded(probe):
			continue
		var block_id := world.get_block(probe)
		if block_id != BlockDB.AIR and BlockDB.is_solid(block_id) and not BlockDB.is_liquid(block_id):
			ground = probe.y + 1
			break
	var home_y := int(state["home"].y)
	if ground == -2147483648 or absi(ground - home_y) > 3:
		state["position"] = Vector3(float(state["home"].x), float(home_y), float(state["home"].z))
		state["task"] = NpcModel.Task.SEEK
		state["target"] = NpcModel.NO_CELL
		state["seek_timer"] = NpcModel.SEEK_RETRY_SECONDS
		return
	state["position"] = Vector3(position.x, float(ground), position.z)


## Re-derives the settlements near the player, creates the residents that are
## missing (a dead resident stays dead) and retires the ones that have moved too
## far away, cap included.
func _refresh_settlements() -> void:
	var feet := Vector3i(floori(player.global_position.x), floori(player.global_position.y),
		floori(player.global_position.z))
	settlements = SettlementModel.nearby(world, feet, int(NpcModel.ACTIVE_RADIUS), 4)
	for settlement: Dictionary in settlements:
		var id := str(settlement["id"])
		_settlement_names[id] = str(settlement["name"])
		if not settlement_stores.has(id):
			settlement_stores[id] = {}
		for resident: Dictionary in NpcModel.residents_for(world.world_seed, settlement):
			var npc_id := str(resident["id"])
			if npc_states.has(npc_id):
				continue
			if npc_states.size() >= NpcModel.CAP * 2:
				break
			npc_states[npc_id] = resident
			print("M17_NPC_SPAWNED id=%s settlement=%s role=%s" % [npc_id, id,
				NpcModel.role_name(int(resident["role"]))])


func _npc_distance(state: Dictionary) -> float:
	var position: Vector3 = state["position"]
	return Vector2(position.x - player.global_position.x, position.z - player.global_position.z).length()


## Adds, updates and retires the scene node of every resident.  A retired node
## keeps its state, so walking away and back resumes the same person.
func _sync_npc_nodes() -> void:
	for id: Variant in npc_states.keys():
		var state: Dictionary = npc_states[id]
		var near := _npc_distance(state) <= NpcModel.ACTIVE_RADIUS
		var node: Variant = npc_nodes.get(id)
		if not near or not bool(state.get("alive", true)):
			if node != null and is_instance_valid(node):
				npc_nodes.erase(id)
				(node as Node).queue_free()
			continue
		if node == null or not is_instance_valid(node):
			var spawned = NpcNodeScript.new()
			spawned.name = "Resident_%s" % str(id).replace(":", "_")
			spawned.configure(state, world)
			npc_root.add_child(spawned)
			spawned.killed.connect(_on_npc_killed)
			npc_nodes[id] = spawned
		else:
			(node as NpcNode).state = state
			# The node walks (physics resolves the ground); if the model jumped
			# (fall recovery) or the body is stuck, put it back where it belongs.
			var body := node as CharacterBody3D
			var expected := Vector3(float(state["position"].x), float(state["position"].y) + 0.2,
				float(state["position"].z))
			var current := body.global_position
			if Vector2(current.x - expected.x, current.z - expected.z).length() > 3.0 \
					or absf(current.y - expected.y) > 2.5:
				body.global_position = expected
				body.velocity = Vector3.ZERO


## Reports what residents did this step.  Deliberately quiet: only a delivery, a
## resident joining a fight or a raider being struck is worth a message.
func _apply_npc_events(state: Dictionary, events: Dictionary) -> void:
	var attack := int(events.get("attack", -1))
	if attack >= 0:
		var threats := _raid_threats()
		if attack < threats.size():
			_damage_nearest_raider(threats[attack], float(events.get("attack_damage", 0.0)), state)
	var delivered: Dictionary = events.get("delivered", {})
	if delivered.is_empty():
		return
	var parts: Array = []
	var keys: Array = delivered.keys()
	keys.sort()
	for item_id in keys:
		parts.append("%d %s" % [int(delivered[item_id]), ItemDB.name_of(int(item_id))])
	hud.flash("%s delivered %s to %s" % [str(state["name"]), " + ".join(parts),
		str(state.get("settlement_name", "the settlement"))], 2.4)


## A resident struck at a raider: the nearest raider node to that position takes
## the damage, so a raid can end without the player lifting a finger.
func _damage_nearest_raider(position: Vector3, damage: float, state: Dictionary) -> void:
	var best: Node = null
	var best_distance := 2.5
	for id: Variant in raid_nodes.keys():
		var node: Variant = raid_nodes[id]
		if node == null or not is_instance_valid(node) or not (node as HostileCreature).is_alive():
			continue
		var distance: float = position.distance_to((node as Node3D).global_position)
		if distance <= best_distance:
			best_distance = distance
			best = node
	if best == null:
		return
	if (best as HostileCreature).apply_hit(int(round(damage))) > 0:
		hud.flash("%s struck a raider down" % str(state.get("name", "A resident")), 2.4)


## A player killed a resident: its carried load drops into the inventory and its
## node goes away.  The state stays (dead) so it is not immediately re-spawned.
func _on_npc_killed(npc) -> void:
	var npc_id := ""
	for id: Variant in npc_nodes.keys():
		if npc_nodes[id] == npc:
			npc_id = str(id)
			break
	if npc_id.is_empty():
		return
	var state: Dictionary = npc_states.get(npc_id, {})
	var collected := 0
	for drop: Dictionary in NpcModel.death_drops(state):
		if inventory.add(int(drop["item"]), int(drop["count"])) == 0:
			collected += int(drop["count"])
	npc_nodes.erase(npc_id)
	if is_instance_valid(npc):
		npc.queue_free()
	hud.flash("%s is dead%s" % [str(state.get("name", "The resident")),
		"" if collected == 0 else "  +%d items" % collected], 2.4)
	hud.refresh()


## One line for the readout when the crosshair is on a resident.
func _npc_target_text() -> String:
	if player == null:
		return ""
	var targeted: Object = player._creature_in_front()
	if targeted == null or not is_instance_valid(targeted) or not (targeted as Node).is_in_group("npc"):
		return ""
	return NpcModel.describe((targeted as NpcNode).state)


## Capture diagnostic (`--follow-resident`): keeps the camera in front of the
## nearest live resident, so a screenshot shows somebody actually working.
func _follow_nearest_resident() -> void:
	var best: Node3D = null
	var best_distance := INF
	for id: Variant in npc_nodes.keys():
		var node: Variant = npc_nodes[id]
		if node == null or not is_instance_valid(node) or not (node as NpcNode).is_alive():
			continue
		var distance: float = player.global_position.distance_to((node as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = node as Node3D
	if best == null:
		return
	var look_at := best.global_position + Vector3(0.0, 0.9, 0.0)
	var offset := Vector3(4.6, 2.8, 4.6)
	var direction := (look_at - (look_at + offset)).normalized()
	player.flying = true
	player.teleport_to(look_at + offset)
	player.look_yaw(rad_to_deg(atan2(-direction.x, -direction.z)))
	player.look_pitch(rad_to_deg(asin(direction.y)))


## Settlement stores and resident state, for the save file.
func _npcs_to_dictionary() -> Dictionary:
	var settlement_rows: Array = []
	var ids: Array = settlement_stores.keys()
	ids.sort()
	for id in ids:
		var store_rows: Array = []
		var items: Array = (settlement_stores[id] as Dictionary).keys()
		items.sort()
		for item_id in items:
			store_rows.append([int(item_id), int((settlement_stores[id] as Dictionary)[item_id])])
		settlement_rows.append({
			"id": str(id),
			"name": str(_settlement_names.get(str(id), "")),
			"store": store_rows,
		})
	var states: Array = []
	var npc_ids: Array = npc_states.keys()
	npc_ids.sort()
	for npc_id in npc_ids:
		states.append(NpcModel.to_dictionary(npc_states[npc_id]))
	return {"settlements": settlement_rows, "npcs": states}

## Restores the stores and the residents from a save.  Anything unreadable is
## dropped rather than turning into a broken resident.  Returns how many residents
## were restored.
func _apply_npcs(payload: Dictionary) -> int:
	settlement_stores.clear()
	npc_states.clear()
	_settlement_names.clear()
	if not payload.is_empty():
		var names := {}
		for row: Variant in (payload.get("settlements", []) as Array):
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var id := str((row as Dictionary).get("id", ""))
			if id.is_empty():
				continue
			names[id] = str((row as Dictionary).get("name", ""))
			_settlement_names[id] = names[id]
			var store := {}
			for entry: Variant in ((row as Dictionary).get("store", []) as Array):
				if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < 2:
					continue
				var item_id := int((entry as Array)[0])
				var count := int((entry as Array)[1])
				if ItemDB.is_valid(item_id) and count > 0:
					store[item_id] = count
			settlement_stores[id] = store
		var restored := 0
		for row: Variant in (payload.get("npcs", []) as Array):
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var payload_row: Dictionary = row
			var state: Dictionary = NpcModel.from_dictionary(payload_row,
				str(names.get(str(payload_row.get("settlement", "")), "")))
			if state.is_empty():
				continue
			npc_states[str(state["id"])] = state
			restored += 1
		return restored
	_refresh_settlements()
	return npc_states.size()


# =========================================================================
# Raids
# =========================================================================
#
# Every other night the raiders come for a settlement near the player.  The
# schedule, the group size and the spawn ring are `core/raid.gd` (pure functions
# of the seed, the day index and the settlement), the raiders are the existing
# grunt node, and the residents defend with the model's DEFEND task.  The result
# is a small, self-resolving fight: residents can die, raiders drop their loot,
# and the player can stand with the settlement or ignore it.

## Starts, tracks and ends the night's raid.  It never steps the residents
## itself: `_update_npcs` does that and passes the raiders as threats.
func _update_raid(delta: float) -> void:
	if world == null or player == null or hostile_root == null or clock == null:
		return
	var day_index := clock.day_index
	var raid_night := RaidModel.is_raid_day(day_index) or bool(_options.get("raid_now", false))
	if not raid_night:
		if not raid_nodes.is_empty():
			_retire_raid()
			hud.flash("Dawn � the raiders are gone", 2.4)
		return
	var settlement := _raid_target(day_index)
	if settlement.is_empty():
		return
	if _raid_settlement != str(settlement["id"]):
		_start_raid(settlement, day_index)
	else:
		_raid_report_timer -= delta
	# The raid is over when nothing is left standing.
	var living := 0
	for id: Variant in raid_nodes.keys():
		var node: Variant = raid_nodes[id]
		if node != null and is_instance_valid(node):
			living += 1
	if _raid_settlement == str(settlement["id"]) and living == 0:
		hud.flash("%s beat off the raid" % str(settlement.get("name", "The settlement")), 3.0)
		_raided_day = day_index
		_retire_raid()


## The settlement a raid should hit tonight: the nearest one to the player, if it
## is a raid night, the player is close enough to see the fight and this world has
## not already raided today.
func _raid_target(day_index: int) -> Dictionary:
	if _raided_day == day_index:
		return {}
	if settlements.is_empty():
		return {}
	var settlement: Dictionary = settlements[0]
	if float(settlement.get("distance", 0.0)) > float(RaidModel.ENGAGE_RADIUS):
		return {}
	if bool(_options.get("raid_now", false)):
		return settlement
	if not RaidModel.should_start(day_index, str(settlement["id"]), float(settlement.get("distance", 0.0)), false):
		return {}
	return settlement


## Spawns tonight's raiders around the settlement and points them at its
## residents, so a raid resolves with or without the player.
func _start_raid(settlement: Dictionary, day_index: int) -> void:
	_retire_raid()
	var anchor: Vector3i = settlement["anchor"]
	var id := str(settlement["id"])
	var count := RaidModel.group_size_for_night(world.world_seed, day_index, id)
	if count <= 0:
		return
	_raid_settlement = id
	_raid_report_timer = 0.0
	hud.flash("Raiders are coming for %s (%d of them)" % [
		str(settlement.get("name", "the settlement")), count], 4.0)
	for index in count:
		var offset := RaidModel.spawn_offset(world.world_seed, day_index, id, index)
		var spawn := Vector3(float(anchor.x) + offset.x + 0.5, float(anchor.y) + 2.0,
			float(anchor.z) + offset.z + 0.5)
		var raider_id := RaidModel.raider_id(day_index, id, index)
		var raider_state := {
			"id": raider_id, "species": "grunt", "position": spawn,
			"health": HostileModel.HIT_POINTS, "alive": true, "key": raider_id,
		}
		var raider = HostileNode.new()
		raider.configure(raider_state, world, _nearest_resident_node(spawn))
		hostile_root.add_child(raider)
		raider.killed.connect(_on_hostile_killed)
		raider.attacked_player.connect(func(amount: float) -> void: _on_raid_hit(raider, amount))
		raid_nodes[raider_id] = raider
	print("M17_RAID_STARTED settlement=%s day=%d raiders=%d" % [id, day_index, count])


## A raider landed a blow: on whoever it is chasing, which may be a resident.
func _on_raid_hit(raider, amount: float) -> void:
	if raider == null or not is_instance_valid(raider):
		return
	var victim: Node = raider.target
	if victim != null and is_instance_valid(victim) and victim.is_in_group("npc"):
		var state: Dictionary = victim.state
		if NpcModel.damage(state, amount):
			hud.flash("%s has been killed by the raiders" % str(state.get("name", "A resident")), 3.0)
			var replacement := _nearest_resident_node(victim.global_position)
			raider.target = replacement if replacement != null else player
		_sync_npc_nodes()
		return
	_on_hostile_attacked_player(amount)


## The nearest live resident's node to a position, or null.
func _nearest_resident_node(position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for id: Variant in npc_nodes.keys():
		var node: Variant = npc_nodes[id]
		if node == null or not is_instance_valid(node) or not (node as NpcNode).is_alive():
			continue
		var distance: float = position.distance_to((node as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = node as Node3D
	return best


## The raiders' positions, for the residents' DEFEND step.
func _raid_threats() -> Array:
	var threats: Array = []
	for id: Variant in raid_nodes.keys():
		var node: Variant = raid_nodes[id]
		if node != null and is_instance_valid(node):
			threats.append((node as Node3D).global_position)
	return threats


## Frees the raiders and clears the raid state (dawn, victory, or a new target).
func _retire_raid() -> void:
	for id: Variant in raid_nodes.keys():
		var node: Variant = raid_nodes[id]
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()
	raid_nodes.clear()
	_raid_settlement = ""
	_raid_report_timer = 0.0
