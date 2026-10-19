class_name GameHUD
extends CanvasLayer

## In-game interface: crosshair, hotbar with real block icons, a status readout
## and a transient message line.
##
## The HUD is presentation only.  It reads the inventory and is told what to
## display; it never mutates game state.

const SLOT_SIZE := 54
const SLOT_GAP := 6
const ICON_MARGIN := 5
## Health / breath readout, bottom-left above the control hint.
const HEALTH_BAR := Vector2(240, 16)
const BREATH_BAR := Vector2(180, 10)
## The hunger bar sits beside the health bar on the same row.
const HUNGER_BAR := Vector2(180, 16)
const HEALTH_ROW_WIDTH := 260.0
const HURT_FLASH_SECONDS := 0.5

var inventory: Inventory
var library: TextureLibrary

var _hotbar: HBoxContainer
var _slots: Array[Panel] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _status: Label
var _selected_label: Label
var _message: Label
var _hint: Label
var _debug: Label
var _crosshair: Control
var _message_timer := 0.0
var _debug_visible := true

var _health_label: Label
var _health_fill: ColorRect
var _health_text := ""
var _hunger_label: Label
var _hunger_fill: ColorRect
var _hunger_text := ""
var _breath_root: Control
var _breath_label: Label
var _breath_fill: ColorRect
var _hurt: ColorRect
var _hurt_timer := 0.0
var _hurt_strength := 0.55
var _durability_bars: Array[ColorRect] = []
var _mining_root: Control
var _mining_fill: ColorRect
var _interact: Label


func setup(player_inventory: Inventory, texture_library: TextureLibrary) -> void:
	inventory = player_inventory
	library = texture_library
	_build()
	inventory.changed.connect(refresh)
	refresh()


func _ready() -> void:
	if inventory != null and not inventory.changed.is_connected(refresh):
		inventory.changed.connect(refresh)
	if _slots.is_empty() and inventory != null:
		_build()
		refresh()


# --- construction --------------------------------------------------------

func _build() -> void:
	layer = 10
	_build_hurt_overlay()
	_crosshair = _build_crosshair()
	_status = _build_label(Vector2(18, 14), 15, Color(1, 1, 1, 0.92))
	_hint = _build_label(Vector2.ZERO, 13, Color(1, 1, 1, 0.62))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 18
	_hint.offset_top = -52
	_hint.offset_right = 780
	_hint.offset_bottom = -14
	_message = _build_label(Vector2.ZERO, 18, Color(1, 1, 1, 0.95))
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_left = -420
	_message.offset_right = 420
	_message.offset_top = 92
	_message.offset_bottom = 122
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.visible = false
	_debug = _build_label(Vector2(18, 128), 13, Color(0.85, 0.95, 1.0, 0.78))
	_interact = _build_label(Vector2.ZERO, 15, Color(1.0, 0.92, 0.65, 0.96))
	_interact.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_interact.offset_left = -260
	_interact.offset_right = 260
	_interact.offset_top = 44
	_interact.offset_bottom = 68
	_interact.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact.visible = false
	_build_hotbar()
	_build_vitals()
	_build_mining_bar()


## A thin progress bar just under the crosshair, shown while a block is being
## mined.  Hardness and the held tool decide how fast it fills.
func _build_mining_bar() -> void:
	_mining_root = Control.new()
	_mining_root.name = "MiningProgress"
	_mining_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_mining_root.offset_left = -60
	_mining_root.offset_right = 60
	_mining_root.offset_top = 26
	_mining_root.offset_bottom = 32
	_mining_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.visible = false
	add_child(_mining_root)
	var background := ColorRect.new()
	background.color = Color(0.03, 0.04, 0.06, 0.7)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.add_child(background)
	_mining_fill = ColorRect.new()
	_mining_fill.color = Color(0.96, 0.89, 0.62, 0.95)
	_mining_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mining_fill.offset_right = 0
	_mining_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.add_child(_mining_fill)


## Shows the mining progress (0..1); 0 hides the bar.
func set_mining_progress(ratio: float) -> void:
	if _mining_root == null:
		return
	var value := clampf(ratio, 0.0, 1.0)
	_mining_root.visible = value > 0.0
	if value > 0.0:
		_mining_fill.size = Vector2(120.0 * value, 6.0)


## A full-screen red tint that pulses on damage.  It is a HUD child drawn first,
## so the crosshair, hotbar and readouts stay legible on top of it.
func _build_hurt_overlay() -> void:
	_hurt = ColorRect.new()
	_hurt.name = "HurtFlash"
	_hurt.color = Color(0.72, 0.03, 0.03, 0.0)
	_hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt)


## Health and breath readouts, placed bottom-left above the control hint.
func _build_vitals() -> void:
	var health_root := Control.new()
	health_root.name = "HealthPanel"
	health_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	health_root.offset_left = 18
	health_root.offset_top = -142
	health_root.offset_right = 18 + HEALTH_BAR.x
	health_root.offset_bottom = -78
	health_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(health_root)

	_health_label = _make_label(15, Color(1, 0.86, 0.86, 0.95))
	_health_label.position = Vector2.ZERO
	health_root.add_child(_health_label)

	var health_bg := ColorRect.new()
	health_bg.color = Color(0.09, 0.02, 0.02, 0.72)
	health_bg.position = Vector2(0, HEALTH_BAR.y + 8)
	health_bg.size = HEALTH_BAR
	health_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_root.add_child(health_bg)
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.86, 0.16, 0.18)
	_health_fill.position = health_bg.position
	_health_fill.size = HEALTH_BAR
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_root.add_child(_health_fill)

	_breath_root = Control.new()
	_breath_root.name = "BreathPanel"
	_breath_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_breath_root.offset_left = 18
	_breath_root.offset_top = -196
	_breath_root.offset_right = 18 + BREATH_BAR.x
	_breath_root.offset_bottom = -142
	_breath_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath_root.visible = false
	add_child(_breath_root)

	_breath_label = _make_label(15, Color(0.82, 0.93, 1.0, 0.95))
	_breath_label.position = Vector2.ZERO
	_breath_root.add_child(_breath_label)
	var breath_bg := ColorRect.new()
	breath_bg.color = Color(0.02, 0.05, 0.09, 0.72)
	breath_bg.position = Vector2(0, BREATH_BAR.y + 8)
	breath_bg.size = BREATH_BAR
	breath_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath_root.add_child(breath_bg)
	_breath_fill = ColorRect.new()
	_breath_fill.color = Color(0.35, 0.72, 0.95)
	_breath_fill.position = breath_bg.position
	_breath_fill.size = BREATH_BAR
	_breath_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath_root.add_child(_breath_fill)

	# Hunger sits on the same row as health, to its right.
	var hunger_root := Control.new()
	hunger_root.name = "HungerPanel"
	hunger_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hunger_root.offset_left = 18 + HEALTH_ROW_WIDTH
	hunger_root.offset_top = -142
	hunger_root.offset_right = 18 + HEALTH_ROW_WIDTH + HUNGER_BAR.x
	hunger_root.offset_bottom = -78
	hunger_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hunger_root)

	_hunger_label = _make_label(15, Color(1.0, 0.92, 0.78, 0.95))
	_hunger_label.position = Vector2.ZERO
	hunger_root.add_child(_hunger_label)

	var hunger_bg := ColorRect.new()
	hunger_bg.color = Color(0.09, 0.06, 0.02, 0.72)
	hunger_bg.position = Vector2(0, HUNGER_BAR.y + 8)
	hunger_bg.size = HUNGER_BAR
	hunger_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hunger_root.add_child(hunger_bg)
	_hunger_fill = ColorRect.new()
	_hunger_fill.color = Color(0.85, 0.62, 0.24)
	_hunger_fill.position = hunger_bg.position
	_hunger_fill.size = HUNGER_BAR
	_hunger_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hunger_root.add_child(_hunger_fill)


func _build_crosshair() -> Control:
	var root := Control.new()
	root.name = "Crosshair"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colour := Color(1, 1, 1, 0.85)
	var shadow := Color(0, 0, 0, 0.5)
	for entry: Array in [
		[Vector2(-11, -1), Vector2(22, 2), shadow],
		[Vector2(-1, -11), Vector2(2, 22), shadow],
		[Vector2(-10, -1), Vector2(20, 2), colour],
		[Vector2(-1, -10), Vector2(2, 20), colour],
	]:
		var line := ColorRect.new()
		line.color = entry[2]
		line.size = entry[1]
		line.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		line.offset_left = (entry[0] as Vector2).x
		line.offset_top = (entry[0] as Vector2).y
		line.offset_right = (entry[0] as Vector2).x + (entry[1] as Vector2).x
		line.offset_bottom = (entry[0] as Vector2).y + (entry[1] as Vector2).y
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(line)
	add_child(root)
	return root


func _build_label(at: Vector2, font_size: int, colour: Color) -> Label:
	var label := _make_label(font_size, colour)
	label.position = at
	add_child(label)
	return label


## Builds a styled label without parenting it, so callers can place it in a panel.
func _make_label(font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_hotbar() -> void:
	var root := Control.new()
	root.name = "HotbarRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	root.offset_top = -(SLOT_SIZE + 34)
	root.offset_bottom = -18
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hotbar = HBoxContainer.new()
	_hotbar.name = "Hotbar"
	_hotbar.add_theme_constant_override("separation", SLOT_GAP)
	_hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hotbar.offset_left = -(Inventory.HOTBAR_SIZE * (SLOT_SIZE + SLOT_GAP)) * 0.5
	_hotbar.offset_right = (Inventory.HOTBAR_SIZE * (SLOT_SIZE + SLOT_GAP)) * 0.5
	_hotbar.offset_top = -SLOT_SIZE * 0.5
	_hotbar.offset_bottom = SLOT_SIZE * 0.5
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hotbar)
	_selected_label = _build_label(Vector2.ZERO, 15, Color(1, 1, 1, 0.95))
	_selected_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_selected_label.offset_left = -300
	_selected_label.offset_right = 300
	_selected_label.offset_top = -(SLOT_SIZE + 30)
	_selected_label.offset_bottom = -(SLOT_SIZE + 4)
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in Inventory.HOTBAR_SIZE:
		_build_slot(index)


func _build_slot(index: int) -> void:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.add_child(panel)
	_slots.append(panel)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = ICON_MARGIN
	icon.offset_top = ICON_MARGIN
	icon.offset_right = -ICON_MARGIN
	icon.offset_bottom = -ICON_MARGIN
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	_icons.append(icon)
	var count := Label.new()
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -20
	count.offset_top = -19
	count.offset_right = -3
	count.offset_bottom = -1
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", 13)
	count.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	count.add_theme_constant_override("shadow_offset_x", 1)
	count.add_theme_constant_override("shadow_offset_y", 1)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(count)
	_counts.append(count)
	# A thin durability bar along the bottom of tool slots; hidden for everything
	# else.  Sits above the icon but inside the slot border.
	var wear := ColorRect.new()
	wear.name = "Durability"
	wear.color = Color(0.42, 0.88, 0.45, 0.95)
	wear.position = Vector2(4, SLOT_SIZE - 7)
	wear.size = Vector2(SLOT_SIZE - 8, 3)
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wear.visible = false
	panel.add_child(wear)
	_durability_bars.append(wear)


# --- state ---------------------------------------------------------------

func refresh() -> void:
	if inventory == null:
		return
	for index in Inventory.HOTBAR_SIZE:
		var panel := _slots[index]
		var item_id := inventory.slots[index]
		var count := inventory.counts[index]
		panel.add_theme_stylebox_override("panel", _slot_style(index == inventory.selected, item_id != BlockDB.AIR))
		_icons[index].texture = _icon_for(item_id)
		var tint := ItemDB.icon_tint(item_id)
		_icons[index].modulate = Color(tint.r, tint.g, tint.b, 1.0 if item_id != BlockDB.AIR else 0.15)
		_counts[index].text = "" if count <= 1 else str(count)
		_refresh_durability(index, item_id)
	var item_id := inventory.selected_item()
	if item_id == BlockDB.AIR:
		_selected_label.text = ""
	else:
		var text := ItemDB.name_of(item_id)
		var max_wear := ItemDB.max_durability(item_id)
		if max_wear > 0:
			text += "   %d / %d" % [inventory.durability_of(inventory.selected), max_wear]
		_selected_label.text = "%s   (slot %d)" % [text, inventory.selected + 1]
	_hint.text = "WASD move  ·  Space jump  ·  Shift sprint  ·  hold LMB mine  ·  RMB build/eat  ·  E use  ·  C recipes  ·  I inventory  ·  O settings\n" \
		+ "1-9 or mouse wheel select  ·  F fly  ·  F5 save  ·  F9 load  ·  F3 debug  ·  Esc pause"


func _refresh_durability(index: int, item_id: int) -> void:
	if index < 0 or index >= _durability_bars.size():
		return
	var bar := _durability_bars[index]
	var maximum := ItemDB.max_durability(item_id)
	if maximum <= 0:
		bar.visible = false
		return
	var ratio := clampf(float(inventory.durability_of(index)) / float(maximum), 0.0, 1.0)
	bar.visible = true
	bar.size = Vector2(maxf(0.0, (SLOT_SIZE - 8) * ratio), 3)
	bar.color = Color(0.42, 0.88, 0.45, 0.95) if ratio > 0.35 \
		else (Color(0.95, 0.78, 0.25, 0.95) if ratio > 0.15 else Color(0.92, 0.30, 0.26, 0.95))


func _icon_for(item_id: int) -> Texture2D:
	if item_id == BlockDB.AIR or library == null:
		return null
	var key := ItemDB.icon_key(item_id)
	if key.is_empty():
		return null
	return library.icon(key)


func _slot_style(selected: bool, occupied: bool) -> StyleBoxFlat:
	return UiStyle.slot_style(occupied, selected)


func set_status(text: String) -> void:
	_status.text = text


## Updates the health readout.  `current`/`maximum` are in health points; the bar
## fills proportionally and the number is always shown.
func set_health(current: float, maximum: float) -> void:
	if _health_label == null:
		return
	_health_text = "HEALTH  %d / %d" % [int(ceil(current)), int(maximum)]
	_health_label.text = _health_text
	var ratio := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	_health_fill.size = Vector2(HEALTH_BAR.x * ratio, HEALTH_BAR.y)


## Updates the breath readout; the panel is only visible while it matters (the
## head is under water or the body is still recovering its breath).
func set_breath(current: float, maximum: float, visible: bool) -> void:
	if _breath_root == null:
		return
	_breath_root.visible = visible
	if not visible:
		return
	_breath_label.text = "BREATH  %d / %d" % [int(ceil(current)), int(maximum)]
	var ratio := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	_breath_fill.size = Vector2(BREATH_BAR.x * ratio, BREATH_BAR.y)


## Current health readout text (used by diagnostics).
func health_text() -> String:
	return _health_text


## Updates the hunger readout.  An empty bar turns red, which is the signal that
## starvation damage has started.
func set_hunger(current: float, maximum: float) -> void:
	if _hunger_label == null:
		return
	_hunger_text = "HUNGER  %d / %d" % [int(ceil(current)), int(maximum)]
	_hunger_label.text = _hunger_text
	var ratio := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	_hunger_fill.size = Vector2(HUNGER_BAR.x * ratio, HUNGER_BAR.y)
	_hunger_fill.color = Color(0.85, 0.62, 0.24) if ratio > 0.0 else Color(0.9, 0.25, 0.2)
	_hunger_label.add_theme_color_override("font_color",
		Color(1.0, 0.92, 0.78, 0.95) if ratio > 0.0 else Color(1.0, 0.55, 0.5, 0.98))


## Current hunger readout text (used by diagnostics).
func hunger_text() -> String:
	return _hunger_text


## Flashes the red damage overlay.  `strength` is the peak alpha.
func hurt_flash(strength: float = 0.55) -> void:
	if _hurt == null:
		return
	_hurt_strength = clampf(strength, 0.0, 1.0)
	_hurt_timer = HURT_FLASH_SECONDS
	_hurt.color = Color(0.72, 0.03, 0.03, _hurt_strength)


## A short prompt under the crosshair ("Press E to use Crafting Table").  An
## empty string hides it.
func set_interact_prompt(text: String) -> void:
	if _interact == null:
		return
	_interact.text = text
	_interact.visible = not text.is_empty()


func set_debug(text: String) -> void:
	_debug.text = text


func toggle_debug() -> void:
	_debug_visible = not _debug_visible
	_debug.visible = _debug_visible
	_status.visible = _debug_visible


func debug_visible() -> bool:
	return _debug_visible


## Text of a hotbar slot's count badge (empty when the count is 1 or the slot is
## empty).  Diagnostic accessor for the runtime test.
func hotbar_count_text(index: int) -> String:
	if index < 0 or index >= _counts.size():
		return ""
	return (_counts[index] as Label).text


func flash(text: String, seconds: float = 2.4) -> void:
	_message.text = text
	_message.visible = true
	_message_timer = seconds


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		_message.modulate.a = clampf(_message_timer, 0.0, 1.0)
		if _message_timer <= 0.0:
			_message.visible = false
	if _hurt_timer > 0.0:
		_hurt_timer = maxf(0.0, _hurt_timer - delta)
		_hurt.color.a = _hurt_strength * clampf(_hurt_timer / HURT_FLASH_SECONDS, 0.0, 1.0)
