"""
Highlight system for voxel world interaction.
Displays visual feedback when looking at blocks.
"""

from ursina import Entity, color

class BlockHighlight:
    """
    Visual highlighting of blocks that can be interacted with.
    """
    
    def __init__(self):
        self.highlight_entity = None
        
    def create_highlight(self, position):
        """Create a visual highlight at given world position."""
        if self.highlight_entity:
            self.highlight_entity.remove()
            
        x, y, z = position
        # Voxel center is at (x+0.5, y+0.5, z+0.5)
        self.highlight_entity = Entity(position=(x + 0.5, y + 0.5, z + 0.5))
        
        # Soft pale yellow highlight with restrained transparency
        highlight_color = color.rgba(255, 255, 180, 200)
        s = 1.006 
        t = 0.012
        
        # 12 edges as thin cube children (local to highlight_entity)
        # Bottom 4
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(s, t, t), position=(0, -s/2, -s/2))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(t, t, s), position=(s/2, -s/2, 0))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(s, t, t), position=(0, -s/2, s/2))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(t, t, s), position=(-s/2, -s/2, 0))
        
        # Top 4
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(s, t, t), position=(0, s/2, -s/2))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(t, t, s), position=(s/2, s/2, 0))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(s, t, t), position=(0, s/2, s/2))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(t, t, s), position=(-s/2, s/2, 0))
        
        # Verticals 4
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(t, s, t), position=(-s/2, 0, -s/2))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(t, s, t), position=(s/2, 0, -s/2))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(t, s, t), position=(s/2, 0, s/2))
        Entity(parent=self.highlight_entity, model='cube', color=highlight_color, scale=(t, s, t), position=(-s/2, 0, s/2))
            
    def update_highlight(self, position):
        """Update highlight position."""
        if self.highlight_entity:
            x, y, z = position
            # Voxel center is at (x+0.5, y+0.5, z+0.5)
            self.highlight_entity.position = (x + 0.5, y + 0.5, z + 0.5)
            
    def remove_highlight(self):
        """Remove the highlight from the scene."""
        if self.highlight_entity:
            self.highlight_entity.remove()
            self.highlight_entity = None
