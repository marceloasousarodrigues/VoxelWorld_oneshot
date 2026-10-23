class_name UiStyle
extends RefCounted

## Shared visual tokens for the gameplay interfaces (M20, extended for M40).
##
## The inventory, crafting table, furnace, HUD and the M40 screen all use the
## same slot dimensions, palette and borders, so one screen never looks like a
## different game.  This is presentation-only data: no state and no model access.

const SLOT_SIZE := 54
const SLOT_ICON_MARGIN := 6
const PANEL_BG := Color(0.045, 0.06, 0.085, 0.97)
const PANEL_BORDER := Color(1, 1, 1, 0.24)
const PANEL_RADIUS := 8
const DETAIL_BG := Color(0.065, 0.085, 0.12, 0.94)
const SLOT_BG_EMPTY := Color(0.07, 0.085, 0.115, 0.72)
const SLOT_BG_FILLED := Color(0.11, 0.13, 0.17, 0.94)
const SLOT_BORDER := Color(1, 1, 1, 0.16)
const SLOT_BORDER_HOVER := Color(0.72, 0.86, 1.0, 0.75)
## M40: the selected slot uses the reference's restrained blue highlight rather
## than the old amber outline.
const SLOT_BORDER_SELECTED := Color(0.55, 0.80, 1.0, 0.98)
const SLOT_BORDER_INVALID := Color(0.95, 0.32, 0.3, 0.85)
const GHOST_BG := Color(0.13, 0.15, 0.1, 0.55)
const TEXT_PRIMARY := Color(0.95, 0.98, 1.0)
const TEXT_SECONDARY := Color(0.70, 0.80, 0.90, 0.92)
const TEXT_MUTED := Color(0.60, 0.70, 0.80, 0.78)
const ACCENT := Color(1.0, 0.9, 0.55)
const READY := Color(0.56, 0.92, 0.58)
const MISSING := Color(0.96, 0.56, 0.52)
const BLOCKED := Color(0.96, 0.78, 0.42)

# --- M40 inventory screen -------------------------------------------------

## The reference's palette: near-black navy panels, blue key highlight, cool
## grey-blue text and a narrow white border that separates overlays from the
## dimmed world behind them.
const SCREEN_SLOT := 48
const SCREEN_SLOT_MARGIN := 5
const SCREEN_PANEL_BG := Color(0.052, 0.066, 0.090, 0.94)
const SCREEN_PANEL_BG_ALT := Color(0.043, 0.055, 0.078, 0.94)
const SCREEN_PANEL_BORDER := Color(0.62, 0.74, 0.90, 0.26)
const SCREEN_PANEL_RADIUS := 10
const SCREEN_DIM := Color(0.012, 0.018, 0.028, 0.62)
const NAV_BG := Color(0.028, 0.038, 0.055, 0.94)
const TAB_SELECTED_BG := Color(0.075, 0.180, 0.300, 0.96)
const TAB_SELECTED_BORDER := Color(0.36, 0.66, 0.98, 0.95)
const TAB_HOVER_BG := Color(0.09, 0.125, 0.175, 0.92)
const TAB_DISABLED := Color(0.50, 0.57, 0.66, 0.34)
const ACCENT_BLUE := Color(0.38, 0.70, 1.0, 0.98)
const KEYCAP_BG := Color(0.075, 0.095, 0.125, 0.96)
const HEART_RED := Color(0.86, 0.16, 0.20, 1.0)
const HEART_DARK := Color(0.16, 0.035, 0.045, 0.96)
const HUNGER_AMBER := Color(0.86, 0.62, 0.28, 1.0)
const BREATH_BLUE := Color(0.36, 0.72, 0.98, 0.95)


## A slot style shared by every inventory-like control.
static func slot_style(occupied: bool, selected: bool = false, ghost: bool = false,
		hovered: bool = false, invalid: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.105, 0.145, 0.88) if ghost \
		else (SLOT_BG_FILLED if occupied else SLOT_BG_EMPTY)
	if invalid:
		style.border_color = SLOT_BORDER_INVALID
	elif selected:
		style.border_color = SLOT_BORDER_SELECTED
	elif hovered:
		style.border_color = SLOT_BORDER_HOVER
	else:
		style.border_color = SLOT_BORDER
	style.set_border_width_all(3 if selected or invalid else (2 if hovered else 1))
	style.set_corner_radius_all(5)
	return style


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(PANEL_RADIUS)
	return style


static func detail_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = DETAIL_BG
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	return style


# --- M40 screen styles ----------------------------------------------------

## The large side panels: translucent navy, soft blue-grey border, 10 px radius.
static func screen_panel_style(alt: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SCREEN_PANEL_BG_ALT if alt else SCREEN_PANEL_BG
	style.border_color = SCREEN_PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(SCREEN_PANEL_RADIUS)
	style.set_content_margin_all(14)
	return style


## A slightly inset block used for the crafting-table note and the hint card.
static func screen_subpanel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.030, 0.040, 0.058, 0.92)
	style.border_color = Color(0.60, 0.72, 0.88, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(10)
	return style


static func nav_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = NAV_BG
	style.border_color = Color(0.62, 0.74, 0.90, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.set_content_margin_all(5)
	return style


static func tab_style(selected: bool, hovered: bool = false, disabled: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_content_margin_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.set_corner_radius_all(7)
	if disabled:
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Color(0, 0, 0, 0)
		style.set_border_width_all(0)
	elif selected:
		style.bg_color = TAB_SELECTED_BG
		style.border_color = TAB_SELECTED_BORDER
		style.set_border_width_all(1)
	elif hovered:
		style.bg_color = TAB_HOVER_BG
		style.border_color = Color(0.62, 0.74, 0.90, 0.24)
		style.set_border_width_all(1)
	else:
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Color(0, 0, 0, 0)
		style.set_border_width_all(0)
	return style


static func keycap_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = KEYCAP_BG
	style.border_color = Color(0.62, 0.74, 0.90, 0.30)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(4)
	return style


## The translucent strip that groups the nine hotbar slots.
static func hotbar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.030, 0.042, 0.060, 0.86)
	style.border_color = Color(0.62, 0.74, 0.90, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.set_content_margin_all(6)
	return style


# --- M40 v2: recipe browser, actions and amount dialog --------------------

## A recipe tile.  Selected tiles use the blue selection border; unavailable
## tiles stay legible but are dimmed by the caller.
static func recipe_tile_style(selected: bool, hovered: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.095, 0.130, 0.96) if selected \
		else (Color(0.085, 0.105, 0.140, 0.94) if hovered else Color(0.045, 0.058, 0.080, 0.92))
	style.border_color = SLOT_BORDER_SELECTED if selected \
		else (Color(0.72, 0.86, 1.0, 0.55) if hovered else Color(0.62, 0.74, 0.90, 0.18))
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(4)
	return style


static func category_style(selected: bool, hovered: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TAB_SELECTED_BG if selected \
		else (TAB_HOVER_BG if hovered else Color(0, 0, 0, 0))
	style.border_color = TAB_SELECTED_BORDER if selected \
		else (Color(0.62, 0.74, 0.90, 0.20) if hovered else Color(0, 0, 0, 0))
	style.set_border_width_all(1 if selected or hovered else 0)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style


static func dialog_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.047, 0.068, 0.985)
	style.border_color = Color(0.62, 0.78, 0.98, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	return style


## Primary (blue) and secondary action buttons for the details/actions panels.
static func button_style(primary: bool, pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if primary:
		style.bg_color = Color(0.10, 0.30, 0.52, 0.98) if not pressed else Color(0.08, 0.24, 0.42, 0.98)
		style.border_color = Color(0.38, 0.70, 1.0, 0.95)
	else:
		style.bg_color = Color(0.075, 0.095, 0.125, 0.94) if not pressed else Color(0.11, 0.14, 0.18, 0.94)
		style.border_color = Color(0.62, 0.74, 0.90, 0.24)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(7)
	return style


static func button_disabled_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.055, 0.075, 0.72)
	style.border_color = Color(0.62, 0.74, 0.90, 0.10)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(7)
	return style
