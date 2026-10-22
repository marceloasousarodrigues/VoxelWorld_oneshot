"""
Highlight system for voxel world interaction.
Displays visual feedback when looking at blocks.
"""

from ursina import Entity, color


class BlockHighlight:
    """
    Visual highlighting of blocks that can be interacted with.

    M16 stutter fix 4: the parent entity and its 12 edge cubes are built once and
    then repositioned. The previous implementation destroyed and re-created all of
    them on every transition between "targeting something" and "targeting
    nothing", which measured 2.203 ms median (p95 3.573 ms) per event; a camera
    swinging across a block boundary produces one such event roughly every 22
    frames. Moving the existing entity costs 0.009 ms, and reusing it also avoids
    the deprecated ``NodePath.remove()`` path that the old code called on every
    removal.

    The public contract is unchanged: ``highlight_entity`` is ``None`` while
    nothing is targeted, and an entity positioned at the targeted block's centre
    with ``visible`` True while something is.
    """

    def __init__(self):
        self.highlight_entity = None
        # The persistent parent, built on first use and never destroyed.
        self._root = None

    def _build_root(self) -> Entity:
        """Create the parent entity and its 12 edge cubes, once."""
        root = Entity()

        # Soft pale yellow highlight with restrained transparency
        highlight_color = color.rgba(255, 255, 180, 200)
        s = 1.006
        t = 0.012

        # 12 edges as thin cube children (local to the root)
        # Bottom 4
        Entity(parent=root, model='cube', color=highlight_color, scale=(s, t, t), position=(0, -s/2, -s/2))
        Entity(parent=root, model='cube', color=highlight_color, scale=(t, t, s), position=(s/2, -s/2, 0))
        Entity(parent=root, model='cube', color=highlight_color, scale=(s, t, t), position=(0, -s/2, s/2))
        Entity(parent=root, model='cube', color=highlight_color, scale=(t, t, s), position=(-s/2, -s/2, 0))

        # Top 4
        Entity(parent=root, model='cube', color=highlight_color, scale=(s, t, t), position=(0, s/2, -s/2))
        Entity(parent=root, model='cube', color=highlight_color, scale=(t, t, s), position=(s/2, s/2, 0))
        Entity(parent=root, model='cube', color=highlight_color, scale=(s, t, t), position=(0, s/2, s/2))
        Entity(parent=root, model='cube', color=highlight_color, scale=(t, t, s), position=(-s/2, s/2, 0))

        # Verticals 4
        Entity(parent=root, model='cube', color=highlight_color, scale=(t, s, t), position=(-s/2, 0, -s/2))
        Entity(parent=root, model='cube', color=highlight_color, scale=(t, s, t), position=(s/2, 0, -s/2))
        Entity(parent=root, model='cube', color=highlight_color, scale=(t, s, t), position=(s/2, 0, s/2))
        Entity(parent=root, model='cube', color=highlight_color, scale=(t, s, t), position=(-s/2, 0, s/2))

        return root

    @staticmethod
    def _centre(position):
        """World position of the centre of the voxel at ``position``."""
        x, y, z = position
        # Voxel center is at (x+0.5, y+0.5, z+0.5)
        return (x + 0.5, y + 0.5, z + 0.5)

    def create_highlight(self, position):
        """Show the highlight at given world position.

        Safe to call when a highlight is already showing: the existing entity is
        moved rather than rebuilt, so the child count never grows.
        """
        if self._root is None:
            self._root = self._build_root()

        self._root.position = self._centre(position)
        self._root.visible = True
        self.highlight_entity = self._root

    def update_highlight(self, position):
        """Update highlight position."""
        if self.highlight_entity:
            self.highlight_entity.position = self._centre(position)

    def remove_highlight(self):
        """Hide the highlight from the scene."""
        if self.highlight_entity:
            self.highlight_entity.visible = False
            self.highlight_entity = None
