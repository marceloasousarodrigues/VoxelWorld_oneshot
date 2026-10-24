class_name HeldItemVisual
extends Node3D

## One held item, built from the game's real item/block data.
##
## Placeable blocks become a small textured cube using the same six face keys as
## the world mesh; food, lumps and decorations keep their transparent item art on
## two crossed quads.  Tools are deliberately modelled voxel props with a grip at
## the node origin.
##
## The tool models use three construction layers rather than a single silhouette:
## a dark, faceted body; a lighter inset face plate; and a narrow cutting-edge
## strip.  That layering is what makes the steel read as forged metal at
## first-person distance, where a single flat colour would disappear.  Handle,
## leather grip, rivets and ferrules use separate materials so wood, leather and
## metal remain distinguishable under the outdoor sun.
##
## This node owns presentation only: the item id still comes from `Inventory`.

const FACE_ORDER := [
	BlockDB.FACE_PX, BlockDB.FACE_NX, BlockDB.FACE_PY,
	BlockDB.FACE_NY, BlockDB.FACE_PZ, BlockDB.FACE_NZ,
]
## Quad normal for each face, used to orient the six small quads.
const FACE_NORMALS := [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
	Vector3.DOWN, Vector3.BACK, Vector3.FORWARD,
]

var item_id := BlockDB.AIR
var cube := false

var _model_scale := 0.45
var _tool_y_offset := 0.0
var _materials: Dictionary = {}


## Replaces this node's children with the visual for `item_id`.
## `size` is the overall model height for tools, the cube edge for blocks or the
## sprite height for flat items.
func build(value: int, library: TextureLibrary, size: float = 0.3) -> void:
	for child in get_children():
		child.free()
	item_id = value
	cube = false
	_model_scale = maxf(0.01, size)
	_tool_y_offset = 0.0
	if value <= BlockDB.AIR or library == null:
		return
	if ItemDB.is_tool_item(value):
		_build_tool(value, _model_scale)
	elif _is_cube_item(value):
		_build_cube(value, library, size)
		cube = true
	else:
		_build_flat(value, library, size)


# --- tools ---------------------------------------------------------------

func _build_tool(value: int, size: float) -> void:
	var palette := _palette(ItemDB.tier(value))
	# Long-handled tools are gripped a little way up the haft in first person.
	# This keeps the head below the reticle without shrinking it, and matches the
	# natural lower-third grip of a carried pickaxe/axe/shovel.  The sword is held
	# by the grip itself, so it keeps its authored origin.
	match ItemDB.tool_class(value):
		ItemDB.Tool.PICKAXE:
			_tool_y_offset = -0.34
			_build_pickaxe(size, palette)
		ItemDB.Tool.AXE:
			_tool_y_offset = -0.18
			_build_axe(size, palette)
		ItemDB.Tool.SHOVEL:
			_tool_y_offset = -0.18
			_build_shovel(size, palette)
		ItemDB.Tool.SWORD:
			_tool_y_offset = 0.0
			_build_sword(size, palette)
		_:
			_bar("Tool", Vector3(0.06, 0.7, 0.06), Vector3(0.0, 0.2, 0.0),
				palette["handle"], Vector3.ZERO, 0.004, 0.0, 0.82)


## Per-tier metal palette.  Every tier keeps the same crisp dark-body / lighter-
## face / bright-edge hierarchy; the hue and brightness identify the material.
## The wooden tier is a forged low-grade head rather than a brown wooden slab:
## the reference design language is a steel head on a warm wooden haft.
func _palette(tier: int) -> Dictionary:
	var metal := Color(0.46, 0.45, 0.42)
	match tier:
		ItemDB.Tier.WOOD:
			metal = Color(0.45, 0.43, 0.39)
		ItemDB.Tier.STONE:
			metal = Color(0.52, 0.54, 0.55)
		ItemDB.Tier.IRON:
			metal = Color(0.62, 0.66, 0.70)
		ItemDB.Tier.DIAMOND:
			metal = Color(0.27, 0.56, 0.53)
	return {
		"metal": metal,
		"metal_dark": metal.darkened(0.40),
		"metal_mid": metal.darkened(0.16),
		"metal_light": metal.lightened(0.12),
		"edge": metal.lightened(0.36),
		"handle": Color(0.35, 0.205, 0.095),
		"handle_light": Color(0.53, 0.335, 0.155),
		"handle_dark": Color(0.23, 0.125, 0.052),
		"leather": Color(0.225, 0.125, 0.062),
		"leather_light": Color(0.40, 0.245, 0.128),
		"brass": Color(0.64, 0.49, 0.22),
		"rivet": metal.lightened(0.30),
	}


## A segmented, tapered haft shared by every long-handled tool.  The three shaft
## sections change width and tone, the front carries thin grain strips, and a
## leather grip plus two metal ferrules stop it reading as one uniform stick.
func _handle(palette: Dictionary, bottom: float, top: float, head_base: float) -> void:
	var lower_top := -0.015
	var mid_top := 0.18
	var upper_top := head_base - 0.060
	_bar("HandleLower", Vector3(0.064, lower_top - bottom, 0.058),
		Vector3(0.0, (bottom + lower_top) * 0.5, 0.0), palette["handle"],
		Vector3.ZERO, 0.006, 0.0, 0.84)
	_bar("HandleMid", Vector3(0.058, mid_top - lower_top + 0.022, 0.053),
		Vector3(0.002, (lower_top + mid_top) * 0.5, 0.0), palette["handle"],
		Vector3(0.0, 0.0, 0.55), 0.005, 0.0, 0.84)
	_bar("HandleUpper", Vector3(0.052, upper_top - mid_top + 0.022, 0.048),
		Vector3(0.0, (mid_top + upper_top) * 0.5, 0.0), palette["handle_light"],
		Vector3(0.0, 0.0, -0.65), 0.005, 0.0, 0.85)
	_bar("HandleNeck", Vector3(0.047, top - upper_top, 0.044),
		Vector3(-0.001, (upper_top + top) * 0.5, 0.0), palette["handle"],
		Vector3.ZERO, 0.004, 0.0, 0.85)
	_bar("HandleEnd", Vector3(0.052, 0.014, 0.049),
		Vector3(0.0, top + 0.005, 0.0), palette["handle_dark"],
		Vector3.ZERO, 0.003, 0.0, 0.88)
	# Raised grain strips on the camera-facing side, deliberately coarse so they
	# still read at gameplay size.
	_bar("GrainLong", Vector3(0.010, 0.26, 0.004),
		Vector3(-0.014, 0.07, -0.0315), palette["handle_light"],
		Vector3.ZERO, 0.001, 0.0, 0.90)
	_bar("GrainShort", Vector3(0.007, 0.13, 0.004),
		Vector3(0.014, 0.19, -0.0290), palette["handle_dark"],
		Vector3.ZERO, 0.001, 0.0, 0.90)
	_bar("GrainKnot", Vector3(0.013, 0.020, 0.004),
		Vector3(0.008, 0.105, -0.0290), palette["handle_dark"],
		Vector3.ZERO, 0.001, 0.0, 0.90)
	# Leather grip: the fist covers its centre, so the raised wraps and the two
	# metal collars show above and below the hand.
	_bar("GripSleeve", Vector3(0.071, 0.200, 0.065),
		Vector3(0.0, -0.010, 0.0), palette["leather"],
		Vector3.ZERO, 0.003, 0.0, 0.94)
	for index in 5:
		var ring_y := -0.096 + float(index) * 0.043
		_bar("GripWrap%d" % index, Vector3(0.075, 0.011, 0.069),
			Vector3(0.0, ring_y, 0.0), palette["leather_light"],
			Vector3.ZERO, 0.002, 0.0, 0.90)
	_bar("GripCollarLow", Vector3(0.076, 0.014, 0.069),
		Vector3(0.0, -0.120, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.002, 0.22, 0.52)
	_bar("GripCollarHigh", Vector3(0.076, 0.014, 0.069),
		Vector3(0.0, 0.100, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.002, 0.22, 0.52)
	# Butt cap and its rivet.
	var pommel_y := bottom + 0.026
	_bar("Pommel", Vector3(0.073, 0.054, 0.067),
		Vector3(0.0, pommel_y, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.006, 0.20, 0.54)
	_bar("PommelRim", Vector3(0.079, 0.012, 0.073),
		Vector3(0.0, bottom + 0.055, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.002, 0.26, 0.44)
	_bar("PommelLeather", Vector3(0.068, 0.036, 0.062),
		Vector3(0.0, bottom + 0.082, 0.0), palette["leather"],
		Vector3.ZERO, 0.002, 0.0, 0.94)
	_disc("PommelRivet", 0.011, 0.014,
		Vector3(0.0, pommel_y, -0.037), palette["rivet"])
	# Head-side ferrule and a second leather binding.
	_bar("Ferrule", Vector3(0.067, 0.062, 0.061),
		Vector3(0.0, head_base - 0.018, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.005, 0.24, 0.50)
	_bar("FerruleRim", Vector3(0.073, 0.014, 0.067),
		Vector3(0.0, head_base + 0.014, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.002, 0.28, 0.42)
	_bar("FerruleWrap", Vector3(0.065, 0.045, 0.059),
		Vector3(0.0, head_base - 0.072, 0.0), palette["leather"],
		Vector3.ZERO, 0.002, 0.0, 0.94)


## The most visible first-person tool.  The head is a broad, downward-swept
## double pick: a heavy central eye with a domed boss, layered arms, a lighter
## inset face and bright cutting tips.  It is deliberately wider than the haft so
## the outline stays unmistakable at gameplay scale.
func _build_pickaxe(size: float, palette: Dictionary) -> void:
	_handle(palette, -0.200, 0.840, 0.605)
	var head_y := 0.695
	var arm := PackedVector2Array([
		Vector2(-0.078, 0.095),
		Vector2(-0.205, 0.107),
		Vector2(-0.330, 0.093),
		Vector2(-0.432, 0.058),
		Vector2(-0.492, -0.005),
		Vector2(-0.468, -0.058),
		Vector2(-0.408, -0.070),
		Vector2(-0.330, -0.030),
		Vector2(-0.205, 0.000),
		Vector2(-0.078, -0.030),
	])
	var face := _scaled_profile(arm, 0.84)
	var top_bevel := PackedVector2Array([
		Vector2(-0.078, 0.095),
		Vector2(-0.205, 0.107),
		Vector2(-0.330, 0.093),
		Vector2(-0.432, 0.058),
		Vector2(-0.452, 0.040),
		Vector2(-0.330, 0.070),
		Vector2(-0.205, 0.084),
		Vector2(-0.078, 0.073),
	])
	var tip := PackedVector2Array([
		Vector2(-0.432, 0.058),
		Vector2(-0.492, -0.005),
		Vector2(-0.468, -0.058),
		Vector2(-0.408, -0.070),
		Vector2(-0.384, -0.044),
		Vector2(-0.438, -0.012),
		Vector2(-0.444, 0.034),
	])
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		var mirrored_arm := arm if side < 0.0 else _mirrored_profile(arm)
		var mirrored_face := face if side < 0.0 else _mirrored_profile(face)
		var mirrored_top := top_bevel if side < 0.0 else _mirrored_profile(top_bevel)
		var mirrored_tip := tip if side < 0.0 else _mirrored_profile(tip)
		_prism("PickArm" + suffix, mirrored_arm, Vector3(0.0, head_y, 0.0), 0.100,
			palette["metal_dark"], Vector3.ZERO, 0.16, 0.58)
		_prism("PickFace" + suffix, mirrored_face, Vector3(0.0, head_y, 0.052), 0.012,
			palette["metal"], Vector3.ZERO, 0.22, 0.50)
		_prism("PickTopBevel" + suffix, mirrored_top, Vector3(0.0, head_y, 0.0), 0.104,
			palette["metal_light"], Vector3.ZERO, 0.27, 0.42)
		_prism("PickEdge" + suffix, mirrored_tip, Vector3(0.0, head_y, 0.0), 0.106,
			palette["edge"], Vector3.ZERO, 0.26, 0.38)
		_bar("PickBolster" + suffix, Vector3(0.068, 0.112, 0.110),
			Vector3(0.105 * side, head_y, 0.0), palette["metal_mid"],
			Vector3.ZERO, 0.006, 0.20, 0.52)
		_bar("PickBolsterRim" + suffix, Vector3(0.074, 0.016, 0.114),
			Vector3(0.105 * side, head_y + 0.048, 0.0), palette["metal_light"],
			Vector3.ZERO, 0.002, 0.26, 0.44)
		_disc("PickRivet" + suffix, 0.011, 0.014,
			Vector3(0.235 * side, head_y + 0.034, 0.056), palette["rivet"])
		_disc("PickRivetOuter" + suffix, 0.009, 0.012,
			Vector3(0.352 * side, head_y + 0.030, 0.056), palette["rivet"])
	# Central eye: a heavy block with a lighter face, a domed boss and four
	# corner rivets.  The haft passes through it and shows as a wooden end cap.
	_bar("PickHub", Vector3(0.205, 0.166, 0.150),
		Vector3(0.0, head_y, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.008, 0.18, 0.56)
	_bar("PickHubFace", Vector3(0.171, 0.132, 0.014),
		Vector3(0.0, head_y, 0.079), palette["metal"],
		Vector3.ZERO, 0.003, 0.24, 0.48)
	_bar("PickHubTop", Vector3(0.178, 0.024, 0.152),
		Vector3(0.0, head_y + 0.078, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.003, 0.28, 0.42)
	_bar("PickHubChin", Vector3(0.160, 0.024, 0.148),
		Vector3(0.0, head_y - 0.078, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.003, 0.22, 0.52)
	_disc("PickBoss", 0.047, 0.020,
		Vector3(0.0, head_y, 0.086), palette["edge"])
	_disc("PickBossInset", 0.029, 0.012,
		Vector3(0.0, head_y, 0.098), palette["metal_light"])
	var hub_rivet := 0
	for dx in [-0.068, 0.068]:
		for dy in [-0.052, 0.052]:
			_disc("PickHubRivet%d" % hub_rivet, 0.010, 0.012,
				Vector3(dx, head_y + dy, 0.087), palette["rivet"])
			hub_rivet += 1
	# Socket below the eye, with a leather binding against the haft.
	_bar("PickSocket", Vector3(0.086, 0.086, 0.073),
		Vector3(0.0, 0.578, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.006, 0.20, 0.54)
	_bar("PickSocketBand", Vector3(0.092, 0.016, 0.079),
		Vector3(0.0, 0.612, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.002, 0.26, 0.44)
	_bar("PickBinding", Vector3(0.067, 0.052, 0.061),
		Vector3(0.0, 0.536, 0.0), palette["leather"],
		Vector3.ZERO, 0.002, 0.0, 0.94)


## A bearded axe with a broad wedge blade, a visible poll and a layered cutting
## edge.  The blade and poll are separate volumes so the head has depth from the
## side, not just a flat decal.
func _build_axe(size: float, palette: Dictionary) -> void:
	_handle(palette, -0.200, 0.800, 0.585)
	var head_y := 0.665
	var blade := PackedVector2Array([
		Vector2(0.030, 0.100),
		Vector2(0.150, 0.140),
		Vector2(0.300, 0.174),
		Vector2(0.416, 0.180),
		Vector2(0.468, 0.112),
		Vector2(0.492, 0.000),
		Vector2(0.466, -0.108),
		Vector2(0.420, -0.178),
		Vector2(0.336, -0.205),
		Vector2(0.306, -0.144),
		Vector2(0.214, -0.088),
		Vector2(0.090, -0.042),
		Vector2(0.030, -0.028),
	])
	var face := _scaled_profile(blade, 0.85)
	var edge := PackedVector2Array([
		Vector2(0.416, 0.180),
		Vector2(0.468, 0.112),
		Vector2(0.492, 0.000),
		Vector2(0.466, -0.108),
		Vector2(0.420, -0.178),
		Vector2(0.384, -0.160),
		Vector2(0.438, -0.100),
		Vector2(0.454, 0.000),
		Vector2(0.430, 0.094),
		Vector2(0.386, 0.158),
	])
	var cheek := _scaled_profile(blade, 0.58)
	_prism("AxeBlade", blade, Vector3(0.0, head_y, 0.0), 0.095,
		palette["metal_dark"], Vector3.ZERO, 0.16, 0.58)
	_prism("AxeFace", face, Vector3(0.0, head_y, 0.050), 0.012,
		palette["metal"], Vector3.ZERO, 0.22, 0.50)
	_prism("AxeCheek", cheek, Vector3(0.0, head_y - 0.042, 0.058), 0.010,
		palette["metal_mid"], Vector3.ZERO, 0.20, 0.54)
	_prism("AxeEdge", edge, Vector3(0.0, head_y, 0.0), 0.099,
		palette["edge"], Vector3.ZERO, 0.26, 0.38)
	_bar("AxePoll", Vector3(0.130, 0.164, 0.100),
		Vector3(-0.074, head_y, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.006, 0.18, 0.56)
	_bar("AxePollFace", Vector3(0.026, 0.112, 0.096),
		Vector3(-0.139, head_y, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.003, 0.28, 0.42)
	_bar("AxeEye", Vector3(0.112, 0.192, 0.104),
		Vector3(0.0, head_y, 0.0), palette["metal_mid"],
		Vector3.ZERO, 0.006, 0.20, 0.52)
	_bar("AxeEyeTop", Vector3(0.118, 0.020, 0.108),
		Vector3(0.0, head_y + 0.098, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.002, 0.28, 0.42)
	_bar("AxeEyeBottom", Vector3(0.106, 0.020, 0.104),
		Vector3(0.0, head_y - 0.098, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.002, 0.22, 0.52)
	_bar("AxeTopLug", Vector3(0.072, 0.036, 0.110),
		Vector3(0.0, head_y + 0.156, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.003, 0.28, 0.42)
	_disc("AxeEyeBoss", 0.028, 0.016,
		Vector3(0.0, head_y, 0.058), palette["metal_light"])
	var axe_rivet := 0
	for at in [Vector2(0.098, 0.075), Vector2(0.232, 0.082)]:
		_disc("AxeRivet%d" % axe_rivet, 0.010, 0.012,
			Vector3(at.x, head_y + at.y, 0.058), palette["rivet"])
		axe_rivet += 1
	_bar("AxeBinding", Vector3(0.070, 0.060, 0.066),
		Vector3(0.0, 0.548, 0.0), palette["leather"],
		Vector3.ZERO, 0.002, 0.0, 0.94)
	_disc("AxeBindingRivet", 0.011, 0.014,
		Vector3(0.0, 0.548, 0.036), palette["brass"])


## A broad spade with a shaped shoulder, a rolled top edge, a raised centre spine
## and two reinforcing rivets.  The blade is layered over a darker body so the
## scoop keeps its silhouette instead of becoming a flat grey plate.
func _build_shovel(size: float, palette: Dictionary) -> void:
	_handle(palette, -0.200, 0.770, 0.545)
	var head_y := 0.700
	var blade := PackedVector2Array([
		Vector2(-0.055, -0.142),
		Vector2(0.055, -0.142),
		Vector2(0.136, -0.072),
		Vector2(0.190, 0.036),
		Vector2(0.198, 0.128),
		Vector2(0.146, 0.166),
		Vector2(0.000, 0.178),
		Vector2(-0.146, 0.166),
		Vector2(-0.198, 0.128),
		Vector2(-0.190, 0.036),
		Vector2(-0.136, -0.072),
	])
	var face := _scaled_profile(blade, 0.84)
	var scoop := _scaled_profile(blade, 0.58)
	var lip := PackedVector2Array([
		Vector2(-0.146, 0.166),
		Vector2(0.000, 0.178),
		Vector2(0.146, 0.166),
		Vector2(0.128, 0.144),
		Vector2(0.000, 0.156),
		Vector2(-0.128, 0.144),
	])
	_prism("ShovelBlade", blade, Vector3(0.0, head_y, 0.0), 0.070,
		palette["metal_dark"], Vector3.ZERO, 0.16, 0.58)
	_prism("ShovelFace", face, Vector3(0.0, head_y, 0.037), 0.012,
		palette["metal"], Vector3.ZERO, 0.22, 0.50)
	_prism("ShovelScoop", scoop, Vector3(0.0, head_y - 0.010, 0.046), 0.008,
		palette["metal_mid"], Vector3.ZERO, 0.18, 0.60)
	_prism("ShovelLip", lip, Vector3(0.0, head_y, 0.0), 0.074,
		palette["edge"], Vector3.ZERO, 0.26, 0.38)
	_bar("ShovelSideLeft", Vector3(0.016, 0.102, 0.074),
		Vector3(-0.191, head_y + 0.082, 0.0), palette["edge"],
		Vector3(0.0, 0.0, 8.0), 0.002, 0.26, 0.40)
	_bar("ShovelSideRight", Vector3(0.016, 0.102, 0.074),
		Vector3(0.191, head_y + 0.082, 0.0), palette["edge"],
		Vector3(0.0, 0.0, -8.0), 0.002, 0.26, 0.40)
	_bar("ShovelSpine", Vector3(0.028, 0.220, 0.078),
		Vector3(0.0, head_y + 0.020, 0.003), palette["metal_light"],
		Vector3.ZERO, 0.003, 0.28, 0.42)
	_bar("ShovelStep", Vector3(0.180, 0.026, 0.080),
		Vector3(0.0, 0.575, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.003, 0.28, 0.42)
	_bar("ShovelSocket", Vector3(0.088, 0.072, 0.075),
		Vector3(0.0, 0.555, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.006, 0.20, 0.54)
	_bar("ShovelBinding", Vector3(0.068, 0.052, 0.062),
		Vector3(0.0, 0.516, 0.0), palette["leather"],
		Vector3.ZERO, 0.002, 0.0, 0.94)
	for index in 2:
		var rivet_x := -0.060 + float(index) * 0.120
		_disc("ShovelRivet%d" % index, 0.010, 0.012,
			Vector3(rivet_x, 0.610, 0.043), palette["rivet"])


## A narrow arming sword with a leather-wrapped grip, a brass guard, a raised
## centre ridge and bright edge strips.  It shares the pickaxe/axe material
## hierarchy so it belongs to the same crafted set.
func _build_sword(size: float, palette: Dictionary) -> void:
	_bar("GripSleeve", Vector3(0.058, 0.238, 0.052),
		Vector3(0.0, -0.055, 0.0), palette["leather"],
		Vector3.ZERO, 0.003, 0.0, 0.94)
	for index in 5:
		_bar("GripRing%d" % index, Vector3(0.062, 0.011, 0.056),
			Vector3(0.0, -0.158 + float(index) * 0.049, 0.0),
			palette["leather_light"], Vector3.ZERO, 0.002, 0.0, 0.90)
	_bar("GripCollar", Vector3(0.068, 0.026, 0.060),
		Vector3(0.0, 0.078, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.003, 0.28, 0.42)
	_bar("Pommel", Vector3(0.084, 0.056, 0.072),
		Vector3(0.0, -0.202, 0.0), palette["metal_dark"],
		Vector3.ZERO, 0.006, 0.22, 0.50)
	_bar("PommelRim", Vector3(0.090, 0.014, 0.078),
		Vector3(0.0, -0.236, 0.0), palette["metal_light"],
		Vector3.ZERO, 0.002, 0.28, 0.42)
	_disc("PommelBoss", 0.023, 0.014,
		Vector3(0.0, -0.202, 0.041), palette["brass"])
	_bar("BladeCollar", Vector3(0.086, 0.032, 0.060),
		Vector3(0.0, 0.208, 0.0), palette["brass"],
		Vector3.ZERO, 0.003, 0.32, 0.38)
	_bar("Guard", Vector3(0.315, 0.048, 0.072),
		Vector3(0.0, 0.180, 0.0), palette["brass"],
		Vector3.ZERO, 0.006, 0.30, 0.42)
	_bar("GuardFace", Vector3(0.220, 0.024, 0.014),
		Vector3(0.0, 0.180, 0.043), palette["metal_light"],
		Vector3.ZERO, 0.002, 0.30, 0.38)
	for sign in [-1.0, 1.0]:
		var suffix := "L" if sign < 0.0 else "R"
		_bar("Quillon" + suffix, Vector3(0.070, 0.042, 0.076),
			Vector3(0.150 * sign, 0.188, 0.0), palette["metal_dark"],
			Vector3(0.0, 0.0, -13.0 * sign), 0.004, 0.22, 0.48)
		_disc("QuillonStud" + suffix, 0.014, 0.012,
			Vector3(0.178 * sign, 0.196, 0.041), palette["brass"])
	_bar("GuardGem", Vector3(0.046, 0.046, 0.020),
		Vector3(0.0, 0.180, 0.048), palette["edge"],
		Vector3(0.0, 0.0, 45.0), 0.003, 0.36, 0.30)
	var blade := PackedVector2Array([
		Vector2(-0.062, 0.185),
		Vector2(0.062, 0.185),
		Vector2(0.054, 0.630),
		Vector2(0.031, 0.812),
		Vector2(0.000, 0.880),
		Vector2(-0.031, 0.812),
		Vector2(-0.054, 0.630),
	])
	_prism("Blade", blade, Vector3.ZERO, 0.030,
		palette["metal_dark"], Vector3.ZERO, 0.26, 0.44)
	var face := _scaled_profile(blade, 0.70)
	_prism("BladeFace", face, Vector3(0.0, 0.0, 0.018), 0.010,
		palette["metal"], Vector3.ZERO, 0.30, 0.38)
	var ridge := PackedVector2Array([
		Vector2(-0.014, 0.230),
		Vector2(0.014, 0.230),
		Vector2(0.010, 0.610),
		Vector2(0.000, 0.700),
		Vector2(-0.010, 0.610),
	])
	_prism("BladeRidge", ridge, Vector3(0.0, 0.0, 0.024), 0.010,
		palette["metal_light"], Vector3.ZERO, 0.32, 0.34)
	for sign in [-1.0, 1.0]:
		var suffix := "L" if sign < 0.0 else "R"
		_bar("BladeEdge" + suffix, Vector3(0.011, 0.500, 0.031),
			Vector3(0.050 * sign, 0.410, 0.0), palette["edge"],
			Vector3(0.0, 0.0, -2.0 * sign), 0.002, 0.34, 0.30)


# --- model helpers -------------------------------------------------------

## A bevelled voxel bar.  `units` and `at` are in model-height fractions; every
## component is multiplied by the overall tool height.  Small chamfers catch the
## light along the silhouette and stop the tools reading as plain cubes.
func _bar(node_name: String, units: Vector3, at: Vector3, colour: Color,
		rotation_degrees: Vector3 = Vector3.ZERO, bevel_units: float = 0.004,
		metallic: float = 0.0, roughness: float = 0.8) -> MeshInstance3D:
	var dimensions := units * _model_scale
	var mesh := _bevelled_mesh(dimensions, bevel_units * _model_scale)
	var instance := _instance(node_name, mesh, at * _model_scale, colour,
		rotation_degrees, metallic, roughness)
	return instance


## A flat extruded profile in the XY plane, centred on its local origin and
## extruded along Z.  Concave profiles (the bearded axe, the pick underside) are
## triangulated properly instead of fanning from one point, so the layered faces
## cannot spill outside the silhouette.
func _prism(node_name: String, profile: PackedVector2Array, at: Vector3,
		depth_units: float, colour: Color, rotation_degrees: Vector3 = Vector3.ZERO,
		metallic: float = 0.0, roughness: float = 0.8) -> MeshInstance3D:
	var scaled := PackedVector2Array()
	for point: Vector2 in profile:
		scaled.append(point * _model_scale)
	var mesh := _prism_mesh(scaled, depth_units * _model_scale)
	return _instance(node_name, mesh, at * _model_scale, colour,
		rotation_degrees, metallic, roughness)


## A low-poly rivet or boss, built as a faceted disc so it catches one hard
## highlight instead of reading as a smooth plastic dome.
func _disc(node_name: String, radius: float, depth_units: float, at: Vector3,
		colour: Color, metallic: float = 0.26, roughness: float = 0.42) -> MeshInstance3D:
	return _prism(node_name, _disc_profile(radius, 10), at, depth_units, colour,
		Vector3.ZERO, metallic, roughness)


func _disc_profile(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments:
		var angle := TAU * float(index) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _scaled_profile(profile: PackedVector2Array, factor: float) -> PackedVector2Array:
	var centre := Vector2.ZERO
	for point: Vector2 in profile:
		centre += point
	centre /= float(maxi(1, profile.size()))
	var scaled := PackedVector2Array()
	for point: Vector2 in profile:
		scaled.append(centre + (point - centre) * factor)
	return scaled


func _mirrored_profile(profile: PackedVector2Array) -> PackedVector2Array:
	var mirrored := PackedVector2Array()
	for point: Vector2 in profile:
		mirrored.append(Vector2(-point.x, point.y))
	return mirrored


func _instance(node_name: String, mesh: Mesh, at: Vector3, colour: Color,
		rotation_degrees: Vector3, metallic: float, roughness: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at + Vector3(0.0, _tool_y_offset * _model_scale, 0.0)
	instance.rotation_degrees = rotation_degrees
	instance.material_override = _material(colour, metallic, roughness)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(instance)
	return instance


func _material(colour: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [colour.to_html(true), metallic, roughness]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	# The authored weights above are relative.  The first-person camera sits in
	# full outdoor sun and the broad blade faces clip to white at a physically
	# high metallic value, so the response is deliberately restrained.
	material.metallic = clampf(metallic * 0.45, 0.0, 0.22)
	material.roughness = maxf(roughness, 0.34)
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	# A trace of emission keeps the wood and dark metal readable in the shade of
	# a roof or canopy without making the tool self-illuminated.
	material.emission_enabled = true
	material.emission = colour * 0.065
	# Custom triangle winding is not meaningful for a convex bevelled/polygon
	# mesh once it is lit; disabling culling also keeps the thin prisms readable
	# from both sides of the hand.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material


## The mesh of a box with all twelve edges chamfered.  Each triangle gets an
## explicitly outward normal for flat, faceted shading.
func _bevelled_mesh(size: Vector3, bevel: float) -> ArrayMesh:
	var h := [size.x * 0.5, size.y * 0.5, size.z * 0.5]
	var limit: float = minf(h[0], minf(h[1], h[2])) * 0.44
	var b: float = clampf(bevel, 0.0, limit)
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if b <= 0.00001:
		# A degenerate chamfer still needs a closed box; b=0 formula works but
		# leaves duplicate edge vertices.  Keep it for tiny parts.
		b = 0.0
	# Six inset faces.
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for sign in [-1.0, 1.0]:
			var normal: Vector3 = axes[a] * sign
			var p0 := _axis_point(a, sign * h[a], u, -(h[u] - b), v, -(h[v] - b))
			var p1 := _axis_point(a, sign * h[a], u, h[u] - b, v, -(h[v] - b))
			var p2 := _axis_point(a, sign * h[a], u, h[u] - b, v, h[v] - b)
			var p3 := _axis_point(a, sign * h[a], u, -(h[u] - b), v, h[v] - b)
			_quad(st, p0, p1, p2, p3, normal)
	# Twelve edge chamfers.
	for a in 3:
		var bb := (a + 1) % 3
		var c := (a + 2) % 3
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var normal: Vector3 = (axes[a] * sa + axes[bb] * sb).normalized()
				var p0 := _axis_point(a, sa * h[a], bb, sb * (h[bb] - b),
					c, h[c] - b)
				var p1 := _axis_point(a, sa * (h[a] - b), bb, sb * h[bb],
					c, h[c] - b)
				var p2 := _axis_point(a, sa * (h[a] - b), bb, sb * h[bb],
					c, -(h[c] - b))
				var p3 := _axis_point(a, sa * h[a], bb, sb * (h[bb] - b),
					c, -(h[c] - b))
				_quad(st, p0, p1, p2, p3, normal)
	# Eight corner triangles.
	for sa in [-1.0, 1.0]:
		for sb in [-1.0, 1.0]:
			for sc in [-1.0, 1.0]:
				var normal: Vector3 = (axes[0] * sa + axes[1] * sb + axes[2] * sc).normalized()
				var p0 := _axis_point(0, sa * h[0], 1, sb * (h[1] - b),
					2, sc * (h[2] - b))
				var p1 := _axis_point(0, sa * (h[0] - b), 1, sb * h[1],
					2, sc * (h[2] - b))
				var p2 := _axis_point(0, sa * (h[0] - b), 1, sb * (h[1] - b),
					2, sc * h[2])
				_tri(st, p0, p1, p2, normal)
	return st.commit()


func _prism_mesh(profile: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := profile.size()
	if count < 3:
		return st.commit()
	var half_depth := maxf(0.0005, depth * 0.5)
	var area := 0.0
	for index in count:
		var p0 := profile[index]
		var p1 := profile[(index + 1) % count]
		area += p0.x * p1.y - p1.x * p0.y
	var ccw := area > 0.0
	var indices := Geometry2D.triangulate_polygon(profile)
	if indices.is_empty():
		var centre := Vector2.ZERO
		for point: Vector2 in profile:
			centre += point
		centre /= float(count)
		for index in count:
			var p0 := profile[index]
			var p1 := profile[(index + 1) % count]
			_tri(st, Vector3(centre.x, centre.y, half_depth),
				Vector3(p0.x, p0.y, half_depth),
				Vector3(p1.x, p1.y, half_depth), Vector3.BACK)
			_tri(st, Vector3(centre.x, centre.y, -half_depth),
				Vector3(p1.x, p1.y, -half_depth),
				Vector3(p0.x, p0.y, -half_depth), Vector3.FORWARD)
	else:
		for offset in range(0, indices.size(), 3):
			var a := profile[int(indices[offset])]
			var b := profile[int(indices[offset + 1])]
			var c := profile[int(indices[offset + 2])]
			_tri(st, Vector3(a.x, a.y, half_depth),
				Vector3(b.x, b.y, half_depth),
				Vector3(c.x, c.y, half_depth), Vector3.BACK)
			_tri(st, Vector3(a.x, a.y, -half_depth),
				Vector3(c.x, c.y, -half_depth),
				Vector3(b.x, b.y, -half_depth), Vector3.FORWARD)
	for index in count:
		var p0 := profile[index]
		var p1 := profile[(index + 1) % count]
		var edge := p1 - p0
		var outward := Vector2(edge.y, -edge.x) if ccw else Vector2(-edge.y, edge.x)
		var side_normal := Vector3(outward.x, outward.y, 0.0).normalized()
		_quad(st,
			Vector3(p0.x, p0.y, half_depth),
			Vector3(p1.x, p1.y, half_depth),
			Vector3(p1.x, p1.y, -half_depth),
			Vector3(p0.x, p0.y, -half_depth), side_normal)
	return st.commit()


func _axis_point(a: int, va: float, b: int, vb: float, c: int, vc: float) -> Vector3:
	var values := [0.0, 0.0, 0.0]
	values[a] = va
	values[b] = vb
	values[c] = vc
	return Vector3(values[0], values[1], values[2])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3) -> void:
	_tri(st, a, b, c, normal)
	_tri(st, a, c, d, normal)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# --- blocks and sprites --------------------------------------------------

## True for blocks whose silhouette is genuinely a cube.  Flowers, crops and
## grass tufts are drawn as their flat art, exactly as the inventory does.
func _is_cube_item(value: int) -> bool:
	if not ItemDB.is_block(value):
		return false
	if value >= BlockDB.face_keys.size():
		return false
	if BlockDB.is_deco(value) or BlockDB.is_flower(value):
		return false
	return true


func _build_cube(value: int, library: TextureLibrary, size: float) -> void:
	var keys: PackedStringArray = BlockDB.face_keys[value]
	for index in 6:
		var face_key := str(keys[FACE_ORDER[index]])
		var texture := library.icon(face_key) if not face_key.is_empty() else null
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.albedo_color = Color.WHITE if texture != null else _fallback_colour(value)
		material.roughness = 0.92
		material.metallic = 0.0
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.cull_mode = BaseMaterial3D.CULL_BACK

		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		var instance := MeshInstance3D.new()
		instance.name = "Face%d" % index
		instance.mesh = quad
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.position = FACE_NORMALS[index] * (size * 0.5)
		# QuadMesh faces +Z; rotate it onto the cube face normal.
		match FACE_NORMALS[index]:
			Vector3.RIGHT:
				instance.rotation.y = PI * 0.5
			Vector3.LEFT:
				instance.rotation.y = -PI * 0.5
			Vector3.UP:
				instance.rotation.x = -PI * 0.5
			Vector3.DOWN:
				instance.rotation.x = PI * 0.5
			Vector3.BACK:
				pass
			Vector3.FORWARD:
				instance.rotation.y = PI
		add_child(instance)


func _build_flat(value: int, library: TextureLibrary, size: float) -> void:
	var key := ItemDB.icon_key(value)
	var texture := library.icon(key) if not key.is_empty() else null
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = ItemDB.icon_tint(value)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.45
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Two perpendicular quads keep the sprite readable while the arm swings.
	for angle in [0.0, PI * 0.5]:
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		var instance := MeshInstance3D.new()
		instance.name = "Sprite"
		instance.mesh = quad
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.rotation.y = angle
		add_child(instance)


func _fallback_colour(value: int) -> Color:
	# A texture-less block still gets a stable, recognisable neutral tint rather
	# than an invisible white cube.
	var hue := fmod(float(value) * 0.61803398875, 1.0)
	return Color.from_hsv(hue, 0.25, 0.62)
