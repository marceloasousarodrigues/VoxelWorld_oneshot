class_name GameHUD
extends CanvasLayer

## In-game interface: crosshair, hotbar with real item icons, health/hunger
## hearts, a status readout and a transient message line (M40 restyle).
##
## The HUD is presentation only.  It reads the inventory and is told what to
## display; it never mutates game state.  Experience and level are not shown
## because the game does not implement them.

const SLOT_SIZE := 54
const SLOT_GAP := 6
const ICON_MARGIN := 5
const HURT_FLASH_SECONDS := 0.5

var inventory: Inventory
var library: TextureLibrary

var _hotbar_root: Control
var _hotbar: HBoxContainer
var _slots: Array[Panel] = []
var _icons: Array[ItemIcon] = []
var _counts: Array[Label] = []
var _status: Label
var _selected_label: Label
var _message: Label
var _hint: Label
var _debug: Label
var _crosshair: Control
var _message_timer := 0.0
var _debug_visible := true

var _vitals: VitalsBar
var _health_text := ""
var _hunger_text := ""
var _hurt: ColorRect
var _hurt_timer := 0.0
var _hurt_strength := 0.55
var _durability_bars: Array[ColorRect] = []
var _mining_root: Control
var _mining_fill: ColorRect
var _interact: Label
var _build_prompt: Label


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
	# A dark backing strip keeps the control hint readable over bright terrain
	# (sand, snow) without covering the hotbar above it.
	var hint_panel := PanelContainer.new()
	hint_panel.name = "ControlHint"
	hint_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint_panel.offset_left = 10
	hint_panel.offset_top = -25
	hint_panel.offset_right = 1010
	hint_panel.offset_bottom = -2
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_theme_stylebox_override("panel", UiStyle.hotbar_style())
	add_child(hint_panel)
	_hint = _make_label(11, Color(1, 1, 1, 0.82))
	hint_panel.add_child(_hint)
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
	_build_prompt = _build_label(Vector2.ZERO, 14, Color(0.88, 0.96, 1.0, 0.94))
	_build_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_build_prompt.offset_left = -380
	_build_prompt.offset_right = 380
	_build_prompt.offset_top = -(SLOT_SIZE + 74)
	_build_prompt.offset_bottom = -(SLOT_SIZE + 50)
	_build_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_prompt.visible = false
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


## Hearts and hunger icons, bottom-left above the control hint.  The values are
## the game's real health and hunger; no XP/level is drawn.
func _build_vitals() -> void:
	_vitals = VitalsBar.new()
	_vitals.name = "Vitals"
	_vitals.setup(library)
	_vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_vitals.offset_left = 10
	_vitals.offset_top = -100
	_vitals.offset_right = 10 + 344
	_vitals.offset_bottom = -62
	add_child(_vitals)


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
	_hotbar_root = Control.new()
	_hotbar_root.name = "HotbarRoot"
	_hotbar_root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hotbar_root.offset_top = -(SLOT_SIZE + 68)
	_hotbar_root.offset_bottom = -34
	_hotbar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotbar_root)

	var strip := PanelContainer.new()
	strip.name = "HotbarStrip"
	strip.add_theme_stylebox_override("panel", UiStyle.hotbar_style())
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	strip.offset_left = -(Inventory.HOTBAR_SIZE * (SLOT_SIZE + SLOT_GAP)) * 0.5 - 8
	strip.offset_right = (Inventory.HOTBAR_SIZE * (SLOT_SIZE + SLOT_GAP)) * 0.5 + 8
	strip.offset_top = -SLOT_SIZE * 0.5 - 6
	strip.offset_bottom = SLOT_SIZE * 0.5 + 16
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar_root.add_child(strip)

	_hotbar = HBoxContainer.new()
	_hotbar.name = "Hotbar"
	_hotbar.add_theme_constant_override("separation", SLOT_GAP)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(_hotbar)

	_selected_label = _build_label(Vector2.ZERO, 14, Color(1, 1, 1, 0.95))
	_selected_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_selected_label.offset_left = -300
	_selected_label.offset_right = 300
	_selected_label.offset_top = -(SLOT_SIZE + 86)
	_selected_label.offset_bottom = -(SLOT_SIZE + 62)
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in Inventory.HOTBAR_SIZE:
		_build_slot(index)


func _build_slot(index: int) -> void:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 1)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.add_child(cell)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(panel)
	_slots.append(panel)
	var icon := ItemIcon.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = ICON_MARGIN
	icon.offset_top = ICON_MARGIN
	icon.offset_right = -ICON_MARGIN
	icon.offset_bottom = -ICON_MARGIN
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
	var wear := ColorRect.new()
	wear.name = "Durability"
	wear.color = Color(0.42, 0.88, 0.45, 0.95)
	wear.position = Vector2(4, SLOT_SIZE - 7)
	wear.size = Vector2(SLOT_SIZE - 8, 3)
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wear.visible = false
	panel.add_child(wear)
	_durability_bars.append(wear)
	var number := Label.new()
	number.text = str(index + 1)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 10)
	number.add_theme_color_override("font_color", Color(1, 1, 1, 0.42))
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(number)


# --- state ---------------------------------------------------------------

func refresh() -> void:
	if inventory == null:
		return
	for index in Inventory.HOTBAR_SIZE:
		var panel := _slots[index]
		var item_id := inventory.slots[index]
		var count := inventory.counts[index]
		panel.add_theme_stylebox_override("panel", _slot_style(index == inventory.selected, item_id != BlockDB.AIR))
		_icons[index].set_item(item_id, library, ItemDB.icon_tint(item_id))
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
		_selected_label.text = text
	_hint.text = "WASD move  ·  Space jump  ·  Shift sprint  ·  LMB mine  ·  RMB build/eat  ·  E use  ·  I inventory  ·  C recipes  ·  O settings  ·  Esc pause"


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


func _slot_style(selected: bool, occupied: bool) -> StyleBoxFlat:
	return UiStyle.slot_style(occupied, selected)


func set_status(text: String) -> void:
	_status.text = text


## Updates the health readout.  `current`/`maximum` are real health points.
func set_health(current: float, maximum: float) -> void:
	_health_text = "HEALTH  %d / %d" % [int(ceil(current)), int(maximum)]
	if _vitals != null:
		_vitals.set_vitals(current, maximum, _hunger_value(), _hunger_max())


## Updates the breath readout; the bar is only visible while it matters.
func set_breath(current: float, maximum: float, visible: bool) -> void:
	if _vitals != null:
		_vitals.set_breath(current, maximum, visible)


## Current health readout text (used by diagnostics).
func health_text() -> String:
	return _health_text


## Updates the hunger readout.  Real hunger points; no fabricated values.
func set_hunger(current: float, maximum: float) -> void:
	_hunger_text = "HUNGER  %d / %d" % [int(ceil(current)), int(maximum)]
	if _vitals != null:
		_vitals.set_vitals(_health_value(), _health_max(), current, maximum)


## Current hunger readout text (used by diagnostics).
func hunger_text() -> String:
	return _hunger_text


func _health_value() -> float:
	return _vitals.health if _vitals != null else 20.0


func _health_max() -> float:
	return _vitals.max_health if _vitals != null else 20.0


func _hunger_value() -> float:
	return _vitals.hunger if _vitals != null else 20.0


func _hunger_max() -> float:
	return _vitals.max_hunger if _vitals != null else 20.0


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


## Live placement feedback under the hotbar: the selected material, the aimed
## face, remaining count and any refusal reason.  Empty text hides it.
func set_build_prompt(text: String, valid: bool = true) -> void:
	if _build_prompt == null:
		return
	_build_prompt.text = text
	_build_prompt.visible = not text.is_empty()
	_build_prompt.add_theme_color_override("font_color",
		Color(0.88, 0.96, 1.0, 0.94) if valid else Color(1.0, 0.70, 0.60, 0.98))


func build_prompt_text() -> String:
	return _build_prompt.text if _build_prompt != null else ""


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
