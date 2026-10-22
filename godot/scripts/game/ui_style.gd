class_name UiStyle
extends RefCounted

## Shared visual tokens for the gameplay interfaces (M20).
##
## The inventory, crafting table, furnace and HUD all use the same slot
## dimensions, palette and borders, so one screen never looks like a different
## game.  This is presentation-only data: no state and no model access.

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
const SLOT_BORDER_SELECTED := Color(1.0, 0.9, 0.55, 0.98)
const SLOT_BORDER_INVALID := Color(0.95, 0.32, 0.3, 0.85)
const GHOST_BG := Color(0.13, 0.15, 0.1, 0.55)
const TEXT_PRIMARY := Color(0.95, 0.98, 1.0)
const TEXT_SECONDARY := Color(0.70, 0.80, 0.90, 0.92)
const TEXT_MUTED := Color(0.60, 0.70, 0.80, 0.78)
const ACCENT := Color(1.0, 0.9, 0.55)
const READY := Color(0.56, 0.92, 0.58)
const MISSING := Color(0.96, 0.56, 0.52)
const BLOCKED := Color(0.96, 0.78, 0.42)


## A slot style shared by every inventory-like control.
static func slot_style(occupied: bool, selected: bool = false, ghost: bool = false,
		hovered: bool = false, invalid: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = GHOST_BG if ghost else (SLOT_BG_FILLED if occupied else SLOT_BG_EMPTY)
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
