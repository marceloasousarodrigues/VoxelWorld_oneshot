from ursina import Entity, Vec3, color, camera
from math import floor
from raycast import raycast


class VoxelPlayer(Entity):
    """
    Player controller for VoxelWorld M6.

    Features:
    - First-person camera
    - WASD movement
    - Mouse look
    - Gravity
    - Ground detection
    - Basic voxel collision
    - Jumping
    - Explicit input state (avoids held_keys dependency)
    """

    def __init__(
        self,
        world,
        spawn_position=None,
        position=None,
        speed=5.0,
        jump_strength=7.0,
        gravity=20.0,
        mouse_sensitivity=40.0,
    ):
        if spawn_position is None:
            spawn_position = position

        if spawn_position is None:
            spawn_position = (8, 10, 8)

        super().__init__(
            position=spawn_position,
            model="cube",
            color=color.clear,
            collider=None,
        )

        self.world = world

        # Interaction state
        self.interaction_state = {
            'left_button': False,
            'right_button': False,
            'last_interaction_point': None,
            'highlighted_block': None
        }

        # Movement
        self.speed = speed
        self.jump_strength = jump_strength
        self.gravity = gravity
        self.velocity_y = 0.0

        # Player dimensions
        self.radius = 0.30
        self.height = 1.80
        self.eye_height = 1.60

        # Mouse
        self.mouse_sensitivity = mouse_sensitivity
        self.camera_pitch = 0.0

        # Explicit keyboard state.
        # This is intentionally used instead of held_keys.
        self.keys = {
            "w": False,
            "a": False,
            "s": False,
            "d": False,
        }

        self.on_ground = False

        # First-person camera
        self._setup_camera()

        # Mouse capture
        self._setup_mouse()

    # ------------------------------------------------------------------
    # SETUP
    # ------------------------------------------------------------------

    def _setup_camera(self):
        """Configure the global Ursina camera for first-person view."""

        camera.parent = self
        camera.position = (0, self.eye_height, 0)
        camera.rotation = (0, 0, 0)
        camera.fov = 90

    def _setup_mouse(self):
        """Enable first-person mouse look."""

        try:
            from ursina import mouse

            mouse.locked = True
            mouse.visible = False
        except Exception:
            pass

    # ------------------------------------------------------------------
    # INPUT
    # ------------------------------------------------------------------

    def input(self, key):
        """
        Handle keyboard input explicitly.

        Ursina sends:
            'w'      -> key pressed
            'w up'   -> key released
        """

        if key == "w":
            self.keys["w"] = True

        elif key == "w up":
            self.keys["w"] = False

        elif key == "a":
            self.keys["a"] = True

        elif key == "a up":
            self.keys["a"] = False

        elif key == "s":
            self.keys["s"] = True

        elif key == "s up":
            self.keys["s"] = False

        elif key == "d":
            self.keys["d"] = True

        elif key == "d up":
            self.keys["d"] = False

        elif key == "space":
            self.jump()

    # ------------------------------------------------------------------
    # UPDATE
    # ------------------------------------------------------------------

    def update(self):
        """Main player update loop."""

        from ursina import time, mouse

        dt = time.dt

        # --------------------------------------------------------------
        # Mouse look
        # --------------------------------------------------------------

        if mouse.locked:
            self.rotation_y += mouse.velocity[0] * self.mouse_sensitivity
            self.camera_pitch -= mouse.velocity[1] * self.mouse_sensitivity

            # Prevent looking completely upside down.
            self.camera_pitch = max(
                -89.0,
                min(89.0, self.camera_pitch),
            )

            camera.rotation_x = self.camera_pitch

        # --------------------------------------------------------------
        # Horizontal movement
        # --------------------------------------------------------------

        self._update_horizontal_movement(dt)

        # --------------------------------------------------------------
        # Vertical movement / gravity
        # --------------------------------------------------------------

        self._update_vertical_movement(dt)

        # --------------------------------------------------------------
        # Interaction logic
        # --------------------------------------------------------------
        self._update_interaction()

        # --------------------------------------------------------------
        # Keep camera synchronized
        # --------------------------------------------------------------

        camera.position = (0, self.eye_height, 0)

    # ------------------------------------------------------------------
    # HORIZONTAL MOVEMENT
    # ------------------------------------------------------------------

    def _update_horizontal_movement(self, dt):
        """Process WASD movement and horizontal collision."""

        forward = Vec3(
            self.forward.x,
            0,
            self.forward.z,
        )

        right = Vec3(
            self.right.x,
            0,
            self.right.z,
        )

        # Avoid normalization errors.
        if forward.length() > 0:
            forward = forward.normalized()

        if right.length() > 0:
            right = right.normalized()

        movement = Vec3(0, 0, 0)

        if self.keys["w"]:
            movement += forward

        if self.keys["s"]:
            movement -= forward

        if self.keys["d"]:
            movement += right

        if self.keys["a"]:
            movement -= right

        if movement.length() <= 0:
            return

        movement = movement.normalized()
        movement *= self.speed * dt

        # Resolve X and Z separately.
        # This prevents diagonal movement from bypassing walls.
        if abs(movement.x) > 0:
            target_x = self.x + movement.x

            if self.can_move_to(
                target_x,
                self.y,
                self.z,
            ):
                self.x = target_x

        if abs(movement.z) > 0:
            target_z = self.z + movement.z

            if self.can_move_to(
                self.x,
                self.y,
                target_z,
            ):
                self.z = target_z

    # ------------------------------------------------------------------
    # VERTICAL MOVEMENT
    # ------------------------------------------------------------------

    def _update_vertical_movement(self, dt):
        """Apply gravity and resolve vertical collision."""

        ground_y = self.find_ground_y()

        # --------------------------------------------------------------
        # Already standing on ground
        # --------------------------------------------------------------

        if (
            ground_y is not None
            and self.velocity_y <= 0
            and abs(self.y - ground_y) <= 0.05
        ):
            self.y = ground_y
            self.velocity_y = 0
            self.on_ground = True
            return

        self.on_ground = False

        # --------------------------------------------------------------
        # Gravity
        # --------------------------------------------------------------

        self.velocity_y -= self.gravity * dt

        new_y = self.y + self.velocity_y * dt

        # --------------------------------------------------------------
        # Falling
        # --------------------------------------------------------------

        if self.velocity_y <= 0:

            if (
                ground_y is not None
                and self.y >= ground_y
                and new_y <= ground_y
            ):
                self.y = ground_y
                self.velocity_y = 0
                self.on_ground = True
                return

            # No ground directly below.
            self.y = new_y
            return

        # --------------------------------------------------------------
        # Rising
        # --------------------------------------------------------------

        if self.can_move_vertical(new_y):
            self.y = new_y
        else:
            # Hit a block above.
            self.velocity_y = 0

    # ------------------------------------------------------------------
    # JUMP
    # ------------------------------------------------------------------

    def jump(self):
        """Jump if the player is standing on solid ground."""

        ground_y = self.find_ground_y()

        if ground_y is None:
            return

        if abs(self.y - ground_y) <= 0.08:
            self.y = ground_y
            self.velocity_y = self.jump_strength
            self.on_ground = False

    # ------------------------------------------------------------------
    # GROUND DETECTION
    # ------------------------------------------------------------------

    def check_ground(self):
        """
        Return True when the player's feet are approximately on a
        solid block.
        """

        ground_y = self.find_ground_y()

        if ground_y is None:
            return False

        return abs(self.y - ground_y) <= 0.08

    def find_ground_y(self):
        """
        Find the top surface of the highest solid block underneath
        the player's footprint.

        Returns:
            float | None
        """

        # Search from slightly above the player's current position.
        # This also handles the case where the initial spawn is
        # slightly inside terrain.
        start_y = max(
            0,
            floor(self.y) + 2,
        )

        # Search downward through the generated world.
        for block_y in range(start_y, -1, -1):

            if self._footprint_has_solid_block(block_y):

                # A block at y=7 has its top at y=8.
                return block_y + 1.0

        return None

    # ------------------------------------------------------------------
    # COLLISION
    # ------------------------------------------------------------------

    def can_move_to(self, x, y, z):
        """
        Check whether the player's body can occupy a horizontal
        position.
        """

        # Player must remain inside the currently generated world.
        if not self._position_inside_generated_world(x, z):
            return False

        # Check several vertical points through the player's body.
        heights = (
            0.05,
            0.80,
            1.50,
            1.75,
        )

        offsets = (
            (0, 0),
            (self.radius, 0),
            (-self.radius, 0),
            (0, self.radius),
            (0, -self.radius),
            (self.radius, self.radius),
            (self.radius, -self.radius),
            (-self.radius, self.radius),
            (-self.radius, -self.radius),
        )

        for ox, oz in offsets:

            for height in heights:

                block = self.get_block_at(
                    x + ox,
                    y + height,
                    z + oz,
                )

                if self.is_block_solid(block):
                    return False

        return True

    def can_move_vertical(self, target_y):
        """
        Check whether the player can move vertically to target_y.

        Used primarily while jumping.
        """

        offsets = (
            (0, 0),
            (self.radius, 0),
            (-self.radius, 0),
            (0, self.radius),
            (0, -self.radius),
        )

        # Check feet, body and head.
        heights = (
            0.05,
            0.80,
            1.50,
            1.75,
        )

        for ox, oz in offsets:

            for height in heights:

                block = self.get_block_at(
                    self.x + ox,
                    target_y + height,
                    self.z + oz,
                )

                if self.is_block_solid(block):
                    return False

        return True

    def body_intersects_solid(self, x, y, z):
        """
        Compatibility helper.

        Returns True if the player's body intersects a solid block.
        """

        offsets = (
            (0, 0),
            (self.radius, 0),
            (-self.radius, 0),
            (0, self.radius),
            (0, -self.radius),
        )

        heights = (
            0.05,
            0.80,
            1.50,
            1.75,
        )

        for ox, oz in offsets:

            for height in heights:

                block = self.get_block_at(
                    x + ox,
                    y + height,
                    z + oz,
                )

                if self.is_block_solid(block):
                    return True

        return False

    # ------------------------------------------------------------------
    # WORLD / CHUNK BOUNDARY
    # ------------------------------------------------------------------

    def _position_inside_generated_world(self, x, z):
        """
        Check whether the player's footprint remains inside a
        currently generated chunk.
        """

        points = (
            (x, z),
            (x + self.radius, z),
            (x - self.radius, z),
            (x, z + self.radius),
            (x, z - self.radius),
        )

        for px, pz in points:

            chunk_coords = self._get_chunk_coords(px, pz)

            if chunk_coords is None:
                return False

            chunk_x, chunk_z = chunk_coords

            if not self._chunk_exists(chunk_x, chunk_z):
                return False

        return True

    def _footprint_has_solid_block(self, block_y):
        """
        Check the player's horizontal footprint at a specific
        block Y coordinate.
        """

        offsets = (
            (0, 0),
            (self.radius, 0),
            (-self.radius, 0),
            (0, self.radius),
            (0, -self.radius),
            (self.radius, self.radius),
            (self.radius, -self.radius),
            (-self.radius, self.radius),
            (-self.radius, -self.radius),
        )

        for ox, oz in offsets:

            block = self.get_block_at(
                self.x + ox,
                block_y,
                self.z + oz,
            )

            if self.is_block_solid(block):
                return True

        return False

    def _get_chunk_coords(self, x, z):
        """
        Convert world coordinates into chunk X/Z coordinates.

        M5 uses 16x16 chunks.
        """

        chunk_size = self._get_chunk_size()

        chunk_x = floor(x / chunk_size)
        chunk_z = floor(z / chunk_size)

        return chunk_x, chunk_z

    def _get_chunk_size(self):
        """Get the world's configured chunk size."""

        # M5 uses 16.
        try:
            value = self.world.chunk_size

            if isinstance(value, int) and value > 0:
                return value
        except Exception:
            pass

        return 16

    def _chunk_exists(self, chunk_x, chunk_z):
        """Check whether a generated chunk exists."""

        # Common World implementations.
        for attribute in (
            "chunks",
            "generated_chunks",
            "_chunks",
        ):

            try:
                chunks = getattr(self.world, attribute)

                if chunks is None:
                    continue

                # Most likely format:
                # {(chunk_x, chunk_y, chunk_z): chunk}
                if (chunk_x, 0, chunk_z) in chunks:
                    return True

                # Alternative format:
                # {(chunk_x, chunk_z): chunk}
                if (chunk_x, chunk_z) in chunks:
                    return True

            except Exception:
                pass

        # If the world exposes a direct getter, use it.
        try:
            chunk = self.world.get_chunk(
                chunk_x,
                0,
                chunk_z,
            )

            return chunk is not None

        except Exception:
            pass

        # Some implementations may use get_chunk(x, z).
        try:
            chunk = self.world.get_chunk(
                chunk_x,
                chunk_z,
            )

            return chunk is not None

        except Exception:
            pass

        return False

    # ------------------------------------------------------------------
    # BLOCK ACCESS
    # ------------------------------------------------------------------

    def get_block_at(self, x, y, z):
        """
        Retrieve a block from the voxel world.

        Converts world coordinates into chunk/local coordinates.
        """

        block_x = floor(x)
        block_y = floor(y)
        block_z = floor(z)

        if block_y < 0:
            return None

        chunk_size = self._get_chunk_size()

        chunk_x = floor(block_x / chunk_size)
        chunk_z = floor(block_z / chunk_size)

        local_x = block_x - chunk_x * chunk_size
        local_z = block_z - chunk_z * chunk_size

        # --------------------------------------------------------------
        # Try direct world API first.
        # --------------------------------------------------------------

        try:
            block = self.world.get_block(
                block_x,
                block_y,
                block_z,
            )

            if block is not None:
                return block

        except Exception:
            pass

        # --------------------------------------------------------------
        # Find the chunk.
        # --------------------------------------------------------------

        chunk = None

        for attribute in (
            "chunks",
            "generated_chunks",
            "_chunks",
        ):

            try:
                chunks = getattr(self.world, attribute)

                if chunks is None:
                    continue

                if (chunk_x, 0, chunk_z) in chunks:
                    chunk = chunks[(chunk_x, 0, chunk_z)]
                    break

                if (chunk_x, chunk_z) in chunks:
                    chunk = chunks[(chunk_x, chunk_z)]
                    break

            except Exception:
                pass

        if chunk is None:

            try:
                chunk = self.world.get_chunk(
                    chunk_x,
                    0,
                    chunk_z,
                )
            except Exception:
                pass

        if chunk is None:

            try:
                chunk = self.world.get_chunk(
                    chunk_x,
                    chunk_z,
                )
            except Exception:
                pass

        if chunk is None:
            return None

        # --------------------------------------------------------------
        # Read block from chunk.
        # --------------------------------------------------------------

        try:
            return chunk.get_block(
                local_x,
                block_y,
                local_z,
            )
        except Exception:
            pass

        try:
            return chunk.get_block(
                (local_x, block_y, local_z)
            )
        except Exception:
            pass

        # Some implementations expose blocks directly.
        try:
            blocks = chunk.blocks

            return blocks[
                local_x,
                block_y,
                local_z,
            ]

        except Exception:
            pass

        try:
            blocks = chunk.blocks

            return blocks[
                (local_x, block_y, local_z)
            ]

        except Exception:
            pass

        return None

    # ------------------------------------------------------------------
    # SOLID BLOCK DETECTION
    # ------------------------------------------------------------------

    def is_block_solid(self, block):
        """
        Determine whether a block is solid.

        M5 terrain is currently composed of GRASS, DIRT and STONE,
        all of which are solid.
        """

        if block is None:
            return False

        # Boolean representation.
        if isinstance(block, bool):
            return block

        # Numeric representation.
        if isinstance(block, (int, float)):
            return block != 0

        # Common block API.
        try:
            if hasattr(block, "solid"):
                return bool(block.solid)
        except Exception:
            pass

        try:
            if hasattr(block, "is_solid"):
                value = block.is_solid

                if callable(value):
                    return bool(value())

                return bool(value)

        except Exception:
            pass

        # String block types.
        if isinstance(block, str):

            return block.upper() not in (
                "",
                "AIR",
                "NONE",
                "0",
            )

        # M5 block enum/object representation.
        try:
            name = block.name

            if name is not None:
                return str(name).upper() not in (
                    "AIR",
                    "NONE",
                )

        except Exception:
            pass

        # If an actual block object exists and no explicit "air"
        # marker was found, treat it as solid.
        return True

    def _update_interaction(self):
        """Handle player interaction with blocks (e.g., block breaking/placing)."""
        from ursina import mouse
        
        # Check left mouse button press for block interaction
        if mouse.left_pressed:
            self.interaction_state['left_button'] = True
            # Perform raycast to find what was clicked
            if self.world:
                direction = self.forward
                origin = self.position + (0, self.eye_height, 0)
                hit_result = raycast(origin, direction, self.world)
                if hit_result:
                    self.interaction_state['last_interaction_point'] = hit_result['position']
                    # Store highlighted block for visual feedback
                    self.interaction_state['highlighted_block'] = hit_result['position']
        else:
            self.interaction_state['left_button'] = False

        # Check right mouse button press for block placing
        if mouse.right_pressed:
            self.interaction_state['right_button'] = True
        else:
            self.interaction_state['right_button'] = False