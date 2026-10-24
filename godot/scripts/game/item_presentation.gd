class_name ItemPresentation
extends RefCounted

## Per-item presentation that is shared by the first-person hand and the
## third-person character.
##
## Keeping the sizes, grip offsets and hand orientations here means neither
## camera has a pile of per-item magic numbers.  The model itself is built by
## `HeldItemVisual` with its origin at the grip: +Y runs up the handle/blade and
## the head sits above the hand.  This class only decides how big that model is
## and how it is turned when held.

## The same item reads at very different sizes a few centimetres from the eye and
## two metres behind the player.  These are deliberately restrained: a natural
## first-person tool should occupy roughly a quarter of the frame, not half of it.
const FP_TOOL_SCALE := 1.0
const TP_TOOL_SCALE := 1.85
const FP_BLOCK_SIZE := 0.145
const TP_BLOCK_SIZE := 0.30
const FP_FLAT_SIZE := 0.155
const TP_FLAT_SIZE := 0.42


## Overall model height in metres before the tool-specific scale is applied.
static func tool_height(item_id: int) -> float:
	match ItemDB.tool_class(item_id):
		ItemDB.Tool.PICKAXE:
			return 0.410
		ItemDB.Tool.AXE:
			return 0.410
		ItemDB.Tool.SHOVEL:
			return 0.370
		ItemDB.Tool.SWORD:
			return 0.400
	return 0.44


## Size argument for `HeldItemVisual.build`.
static func item_size(item_id: int, third_person: bool) -> float:
	if ItemDB.is_tool_item(item_id):
		return tool_height(item_id) * (TP_TOOL_SCALE if third_person else FP_TOOL_SCALE)
	if ItemDB.is_block(item_id) and not is_flat_block(item_id):
		return TP_BLOCK_SIZE if third_person else FP_BLOCK_SIZE
	return TP_FLAT_SIZE if third_person else FP_FLAT_SIZE


static func is_flat_block(item_id: int) -> bool:
	if not ItemDB.is_block(item_id) or item_id >= BlockDB.face_keys.size():
		return false
	return BlockDB.is_deco(item_id) or BlockDB.is_flower(item_id)


## Hand orientation in camera space while the first-person arm is at rest.
## Positive X tilts the top away from the eye, negative Z leans it to the right.
## The values are intentionally small: the tool should look carried, not staged.
static func first_person_rotation_degrees(item_id: int) -> Vector3:
	match ItemDB.tool_class(item_id):
		ItemDB.Tool.PICKAXE:
			return Vector3(-10.0, -22.0, -32.0)
		ItemDB.Tool.AXE:
			return Vector3(-8.0, -28.0, -22.0)
		ItemDB.Tool.SHOVEL:
			return Vector3(-9.0, -18.0, -15.0)
		ItemDB.Tool.SWORD:
			return Vector3(-6.0, -10.0, -45.0)
	return Vector3.ZERO


## Small offset from the grip origin.  A block is held above the closed fist;
## tools need no offset because their handle already passes through the hand.
static func first_person_offset(item_id: int) -> Vector3:
	if ItemDB.is_tool_item(item_id):
		return Vector3.ZERO
	if ItemDB.is_block(item_id) and not is_flat_block(item_id):
		return Vector3(0.015, 0.075, -0.005)
	return Vector3(0.008, 0.045, 0.0)


## Rotation relative to the shoulder pivot for the third-person body.  The arm
## hangs down at rest, so an identity rotation would run the tool up the sleeve.
## A sword is angled down and forward; the long-handled tools stand head-up so
## their silhouette reads from behind.
static func third_person_rotation_degrees(item_id: int) -> Vector3:
	match ItemDB.tool_class(item_id):
		ItemDB.Tool.PICKAXE:
			return Vector3(-10.0, 4.0, -18.0)
		ItemDB.Tool.AXE:
			return Vector3(-9.0, 4.0, -17.0)
		ItemDB.Tool.SHOVEL:
			return Vector3(-8.0, 2.0, -14.0)
		ItemDB.Tool.SWORD:
			return Vector3(136.0, 6.0, -18.0)
	return Vector3.ZERO


static func third_person_offset(item_id: int) -> Vector3:
	if ItemDB.is_tool_item(item_id):
		return Vector3(0.015, 0.015, 0.02)
	if ItemDB.is_block(item_id) and not is_flat_block(item_id):
		return Vector3(0.02, 0.085, -0.02)
	return Vector3(0.01, 0.05, 0.0)
