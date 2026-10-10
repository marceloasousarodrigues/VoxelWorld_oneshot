from pathlib import Path

from ursina import Button, Entity, Text, camera, color

from block_data import BlockType, get_block_face_textures

TEXTURE_MAP = {
    BlockType.GRASS: (0.0, 1 / 3),
    BlockType.DIRT: (1 / 3, 2 / 3),
    BlockType.STONE: (2 / 3, 1.0),
}

class InventoryUI:
    def __init__(self, inventory):
        self.inventory = inventory
        self.inventory.on_changed = self.update_slots
        self.ui_entity = Entity(parent=camera.ui, enabled=False)
        self.slots = []
        self.slot_icons = []
        self.slot_texts = []

        # Hotbar (first 9 slots)
        for i in range(9):
            b = Button(
                parent=self.ui_entity,
                position=(-0.4 + i * 0.1, -0.4, 0),
                scale=0.08,
                color=color.gray,
                unlit=True,
            )
            self.slots.append(b)

            icon = Entity(
                parent=b,
                model='quad',
                texture=None,
                visible=False,
                unlit=True,
                z=-0.1,
            )
            self.slot_icons.append(icon)
            
            # Use z=-0.2 to avoid z-fighting and always_on_top for readability
            text = Text(parent=b, text='', position=(0.3, -0.3, -0.2), scale=2, visible=False, always_on_top=True)
            self.slot_texts.append(text)
        
        # selection_indicator is now a container for border edges
        self.selection_indicator = Entity(parent=self.ui_entity, position=self.slots[0].position, z=-0.5)
        
        # 4 edges as thin quad children (local to selection_indicator)
        # Offset to fit the buttons (scale 0.08)
        s = 0.08
        t = 0.005
        # Top
        Entity(parent=self.selection_indicator, model='quad', color=color.yellow, scale=(s, t), position=(0, s/2))
        # Bottom
        Entity(parent=self.selection_indicator, model='quad', color=color.yellow, scale=(s, t), position=(0, -s/2))
        # Left
        Entity(parent=self.selection_indicator, model='quad', color=color.yellow, scale=(t, s), position=(-s/2, 0))
        # Right
        Entity(parent=self.selection_indicator, model='quad', color=color.yellow, scale=(t, s), position=(s/2, 0))

    def update_selection(self, index):
        if 0 <= index < len(self.slots):
            pos = self.slots[index].position
            self.selection_indicator.position = (pos.x, pos.y, -0.5)

    def update_slots(self):
        # Update hotbar icons and text
        for i in range(9):
            item = self.inventory.get_selected_item(i)
            if item and item.quantity > 0:
                self.slot_icons[i].visible = True
                # Prefer per-file texture from voxel_textures/blocks/ using the manifest-style face mapping.
                # Fallback to legacy atlas strip (voxel_textures/blocks.png) when not available.
                faces = get_block_face_textures(item.item_type)
                side_path = faces.get('side')

                icon = self.slot_icons[i]
                if side_path:
                    icon.texture = side_path
                    if hasattr(icon, 'texture_offset'):
                        icon.texture_offset = (0, 0)
                    if hasattr(icon, 'texture_scale'):
                        icon.texture_scale = (1, 1)
                else:
                    icon.texture = 'voxel_textures/blocks.png'
                    u0, _u1 = TEXTURE_MAP.get(item.item_type, (0.0, 1 / 3))
                    icon.texture_offset = (u0, 0)
                    icon.texture_scale = (1 / 3, 1)

                self.slot_texts[i].visible = True
                self.slot_texts[i].text = str(item.quantity)
            else:
                self.slot_icons[i].visible = False
                self.slot_texts[i].visible = False

    def toggle(self):
        self.ui_entity.enabled = not self.ui_entity.enabled
        self.update_slots()
