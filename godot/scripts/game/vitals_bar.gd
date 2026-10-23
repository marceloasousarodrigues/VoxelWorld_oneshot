class_name VitalsBar
extends Control

## Health, hunger and breath, drawn as the reference's heart/meat rows (M40).
##
## Presentation only: the game passes the authoritative health/hunger/breath
## values, and this control never invents, heals or drains anything.  There is no
## experience or level display because VoxelWorld does not implement those
## systems; showing a number here would be fabricated state.
##
## Hearts are 20 health points expressed as ten 2-point hearts, matching the
## existing `Health.DEFAULT_MAX_HEALTH`.  Hunger is 20 points as ten units,
## matching `Survival.MAX_HUNGER`.

const UNITS := 10
const HEART_SIZE := 14.0
const HEART_GAP := 2.0
const HUNGER_SIZE := 15.0
const HUNGER_GAP := 2.0
const ROW_HEIGHT := 18.0
const BREATH_HEIGHT := 4.0
const HUNGER_ICON_KEY := "item_cooked_meat"

var health := 20.0
var max_health := 20.0
var hunger := 20.0
var max_hunger := 20.0
var breath := 15.0
var max_breath := 15.0
var breath_visible := false

var library: TextureLibrary


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(344, ROW_HEIGHT + BREATH_HEIGHT + 6.0)


func setup(texture_library: TextureLibrary = null) -> void:
	library = texture_library
	queue_redraw()


func set_vitals(health_value: float, health_max: float, hunger_value: float,
		hunger_max: float) -> void:
	health = maxf(0.0, health_value)
	max_health = maxf(1.0, health_max)
	hunger = maxf(0.0, hunger_value)
	max_hunger = maxf(1.0, hunger_max)
	tooltip_text = summary_text()
	queue_redraw()


func set_breath(breath_value: float, breath_max: float, visible: bool) -> void:
	breath = maxf(0.0, breath_value)
	max_breath = maxf(0.001, breath_max)
	breath_visible = visible
	queue_redraw()


## Human-readable real state, used by the HUD and the character page.
func summary_text() -> String:
	return "Health %d/%d  ·  Hunger %d/%d" % [
		int(ceil(health)), int(ceil(max_health)),
		int(ceil(hunger)), int(ceil(max_hunger)),
	]


func _draw() -> void:
	var heart_width := UNITS * HEART_SIZE + (UNITS - 1) * HEART_GAP
	for unit in UNITS:
		var at := Vector2(unit * (HEART_SIZE + HEART_GAP), 1.0)
		var per_unit := max_health / float(UNITS)
		var value := clampf(health - float(unit) * per_unit, 0.0, per_unit)
		_draw_heart(at, value / per_unit)
	var hunger_x := heart_width + 14.0
	var texture := library.icon(HUNGER_ICON_KEY) if library != null else null
	for unit in UNITS:
		var at := Vector2(hunger_x + unit * (HUNGER_SIZE + HUNGER_GAP), 0.0)
		var per_unit := max_hunger / float(UNITS)
		var value := clampf(hunger - float(unit) * per_unit, 0.0, per_unit)
		_draw_hunger_unit(at, value / per_unit, texture)
	if breath_visible:
		_draw_breath()


func _draw_heart(at: Vector2, ratio: float) -> void:
	# A dark silhouette keeps the empty hearts legible on any background.
	_heart_shape(at, UiStyle.HEART_DARK, false)
	if ratio >= 0.75:
		_heart_shape(at, UiStyle.HEART_RED, true)
	elif ratio >= 0.25:
		# Half heart: left lobe and left half of the point in red.
		var s := HEART_SIZE
		var left := at + Vector2(s * 0.12, s * 0.34)
		var middle := at + Vector2(s * 0.50, s * 0.34)
		var tip := at + Vector2(s * 0.50, s * 0.90)
		draw_circle(at + Vector2(s * 0.30, s * 0.33), s * 0.22, UiStyle.HEART_RED, true, -1.0, true)
		draw_colored_polygon(PackedVector2Array([left, middle, tip]), UiStyle.HEART_RED)


func _heart_shape(at: Vector2, colour: Color, inset: bool) -> void:
	var s := HEART_SIZE
	var radius := s * (0.20 if inset else 0.26)
	var centre_y := s * (0.34 if inset else 0.35)
	draw_circle(at + Vector2(s * 0.30, centre_y), radius, colour, true, -1.0, true)
	draw_circle(at + Vector2(s * 0.70, centre_y), radius, colour, true, -1.0, true)
	var shoulder := s * (0.40 if inset else 0.38)
	var spread := s * (0.38 if inset else 0.44)
	var tip := s * (0.88 if inset else 0.94)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(s * 0.5 - spread, shoulder),
		at + Vector2(s * 0.5 + spread, shoulder),
		at + Vector2(s * 0.5, tip),
	]), colour)


func _draw_hunger_unit(at: Vector2, ratio: float, texture: Texture2D) -> void:
	var rect := Rect2(at, Vector2(HUNGER_SIZE, HUNGER_SIZE))
	if texture != null:
		var alpha := 1.0 if ratio >= 0.5 else (0.42 if ratio > 0.0 else 0.18)
		draw_texture_rect(texture, rect, false, Color(1, 1, 1, alpha))
		return
	# No texture library (headless): a simple amber drumstick silhouette.
	var colour := UiStyle.HUNGER_AMBER if ratio > 0.0 else Color(0.35, 0.26, 0.14, 0.7)
	draw_circle(at + Vector2(HUNGER_SIZE * 0.42, HUNGER_SIZE * 0.40), HUNGER_SIZE * 0.22, colour, true, -1.0, true)
	draw_rect(Rect2(at + Vector2(HUNGER_SIZE * 0.50, HUNGER_SIZE * 0.52),
		Vector2(HUNGER_SIZE * 0.30, HUNGER_SIZE * 0.12)), colour)


func _draw_breath() -> void:
	var bar_width := 180.0
	var at := Vector2(0.0, ROW_HEIGHT + 3.0)
	draw_rect(Rect2(at, Vector2(bar_width, BREATH_HEIGHT)), Color(0.02, 0.05, 0.09, 0.85))
	var ratio := clampf(breath / max_breath, 0.0, 1.0)
	draw_rect(Rect2(at, Vector2(bar_width * ratio, BREATH_HEIGHT)), UiStyle.BREATH_BLUE)
