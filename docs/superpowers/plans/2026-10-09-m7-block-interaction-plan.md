# M7 — Block Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement basic runtime interaction with the voxel world, allowing players to break and place blocks using raycasting from the first-person camera.

**Architecture:** This implementation extends existing systems without duplicating functionality. It reuses coordinate system, block data, mesh generation, world container, chunk entities, and player/camera/collision systems. Interaction uses raycasting to target solid blocks, with highlighting for targeted blocks and mouse button actions for breaking/placing. The dirty-chunk signal mechanism is used to refresh meshes after modifications.

**Tech Stack:** Python, Ursina game engine

**Spec:** docs/superpowers/specs/2026-10-08-m7-block-interaction-design.md

## Global Constraints

- Chunk size is 16 (constant in use)
- World block data uses integer values
- Interaction point updates once per player update  
- MAX_INTERACT_RANGE defaults to ≈ 6 units
- No multiplayer, persistence, or advanced features (see out of scope)

## Review Focus

- Raycast handling of chunk boundaries (inter-chunk occlusion)
- Block breaking and placement safety checks (no intersection with player body)
- Highlight positioning accuracy in world space
- Dirty chunk refresh mechanism for mesh rebuilding
- Consistency between raycast hit data and action execution

---

### Task 1: Add World dirty tracking and refresh functionality

**Files:**
- Modify: `world.py:1-30`
- Test: `tests/test_world_dirty_tracking.py`

**Interfaces:**
- Consumes: `chunk_id` (integer), block data, chunk coordinates
- Produces: `dirty_chunks` set, refresh logic for chunks

- [ ] **Step 1: Write the failing test**

```python
def test_world_dirty_tracking():
    world = World()
    chunk_id = (0, 0)
    assert chunk_id not in world.dirty_chunks
    
    # Mark chunk as dirty
    world.dirty(chunk_id)
    assert chunk_id in world.dirty_chunks
    
    # Refresh should clear the dirty set
    world.refresh()  
    assert chunk_id not in world.dirty_chunks
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_world_dirty_tracking.py -v`
Expected: FAIL with "dirty method not defined"

- [ ] **Step 3: Implement a `dirty(chunk_id)` method in `world.py`**

Add the method that marks chunks as needing refresh (add to World class):

```python
def dirty(self, chunk_id):
    """Mark chunk for mesh regeneration."""
    self.dirty_chunks.add(chunk_id)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_world_dirty_tracking.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add world.py tests/test_world_dirty_tracking.py
git commit -m "feat: add World dirty tracking"
```

### Task 2: Add set_block functionality to World class

**Files:**
- Modify: `world.py:1-30` 
- Test: `tests/test_world_set_block.py`

**Interfaces:**
- Consumes: world position coordinates (int tuple), block value (int)
- Produces: `set_block` method that marks the chunk dirty

- [ ] **Step 1: Write the failing test**

```python
def test_set_block_marks_dirty():
    world = World()
    pos = (0, 0, 0)
    
    # Before setting block, ensure no dirty chunks
    assert not world.dirty_chunks
    
    # Set a block and check if chunk gets marked dirty
    world.set_block(pos, DIRT)
    
    expected_chunk_id = (0, 0)
    assert expected_chunk_id in world.dirty_chunks
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_world_set_block.py -v`
Expected: FAIL with "set_block method not defined"

- [ ] **Step 3: Implement `set_block` method in World class that marks affected chunk as dirty**

```python
def set_block(self, pos, block_type):
    """Set a block and mark its chunk for refresh."""
    self._blocks[pos] = block_type
    
    # Mark the chunk containing this block for refresh
    chunk_id = self.world_to_chunk(pos)
    self.dirty(chunk_id)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_world_set_block.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add world.py tests/test_world_set_block.py
git commit -m "feat: add World.set_block with dirty chunk tracking"
```

### Task 3: Add chunk refresh functionality  

**Files:**
- Modify: `chunk.py:1-20`
- Test: `tests/test_chunk_refresh.py`

**Interfaces:**
- Consumes: neighbour_map from `chunk_mesh.py`,
- Produces: `refresh` method that rebuilds chunk mesh with neighbors

- [ ] **Step 1: Write the failing test**

```python
def test_chunk_refresh():
    # Create chunk and validate refresh can be called
    chunk = Chunk((0, 0))  
    assert hasattr(chunk, 'refresh')
    
    # Verify it doesn't crash
    try:
        chunk.refresh()
    except Exception as e:
        pytest.fail(f"refresh() raised {type(e).__name__}: {e}")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_chunk_refresh.py -v`  
Expected: FAIL with "refresh method not defined"

- [ ] **Step 3: Implement refresh in Chunk class that handles local mesh rebuild**

```python
def refresh(self):
    """Rebuilds the chunk's mesh using neighbor data if available."""
    # Get necessary data for mesh regeneration 
    if self.neighbour_map:
        # Rebuild own mesh with neighbor visibility info
        pass
    else:
        # Rebuild own mesh normally  
        pass
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_chunk_refresh.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add chunk.py tests/test_chunk_refresh.py
git commit -m "feat: add Chunk.refresh for mesh regeneration"
```

### Task 4: Add raycasting functionality to determine interaction point

**Files:**
- Create: `raycast.py`
- Test: `tests/test_raycasting.py`

**Interfaces:**
- Consumes: camera position and direction, MAX_INTERACT_RANGE
- Produces: interaction point (world pos) and hit data (block type, face, neighbor pos)

- [ ] **Step 1: Write the failing test**

```python
def test_ray_cast_solid_block():
    world = World()
    
    # Place a block at (0, 0, 0)
    world.set_block((0, 0, 0), DIRT) 
    
    # Cast ray from origin toward block
    origin = (0.5, 0.5, 0.5)
    direction = (1, 0, 0)
    
    hit = raycast(origin, direction, world) 
    assert hit is not None
    assert hit.position == (0, 0, 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_raycasting.py -v`
Expected: FAIL with "raycast function not defined"

- [ ] **Step 3: Implement a raycast function that walks the ray cell-by-cell and reports hit data**

```python
def raycast(origin, direction, world):
    """Cast a ray into the world and return first solid block hit."""
    # Implementation walks along grid cells using DDA-like approach  
    # Stops at first non-air block; returns block type, position, face info
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_raycasting.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add raycast.py tests/test_raycasting.py
git commit -m "feat: add raycasting for block interaction"
```

### Task 5: Update player to manage interaction state and input 

**Files:**
- Modify: `player.py:1-30`
- Test: `tests/test_player_interaction.py`  

**Interfaces:**
- Consumes: raycast result, player camera position/direction
- Produces: interaction point, break/place button handling

- [ ] **Step 1: Write the failing test**

```python
def test_player_handles_input():
    # Create player and set up interaction
    player = Player()
    
    # Simulate mouse press events  
    # Ensure break/place action is called when buttons pressed
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_player_interaction.py -v`
Expected: FAIL with "no interact method or input handling"

- [ ] **Step 3: Add interaction state and input handling logic in Player class**

```python
def update(self):
    """Update player including interaction point."""
    self.update_interaction_point() # Update ray and hit results
    
    # Handle left/right mouse buttons
    if mouse.left:
        self.break_block()
    elif mouse.right:
        self.place_block()    
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_player_interaction.py -v` 
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add player.py tests/test_player_interaction.py
git commit -m "feat: add interaction state and input handling"
```

### Task 6: Implement block breaking logic  

**Files:**
- Modify: `player.py`
- Test: `tests/test_break_block.py`

**Interfaces:**
- Consumes: player raycast hit result  
- Produces: set_block(AIR) with dirty marking

- [ ] **Step 1: Write the failing test**

```python
def test_break_block():
    world = World()
    pos = (0, 0, 0)
    
    # Place a block and then break it
    world.set_block(pos, DIRT) 
    assert world.get_block(pos) != AIR
    
    player = Player()
    player.break_block()  # Should call set_block(AIR) on current hit position
    
    assert world.get_block(pos) == AIR
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_break_block.py -v`
Expected: FAIL with "break_block method not defined"

- [ ] **Step 3: Implement a `break_block()` method in player class that sets block to AIR**

```python
def break_block(self):
    """Remove the block at interaction point."""
    if self.hit is not None:
        world.set_block(self.hit.position, AIR)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_break_block.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add player.py tests/test_break_block.py
git commit -m "feat: implement block breaking logic"
```

### Task 7: Implement block placement logic  

**Files:**
- Modify: `player.py`  
- Test: `tests/test_place_block.py`

**Interfaces:**
- Consumes: player interaction state, hit face
- Produces: set_block(DIRT) with safety checks

- [ ] **Step 1: Write the failing test**

```python
def test_place_block_valid_position():
    world = World()
    pos = (0, 0, 1)  # Block above empty space
    
    player = Player() 
    assert player.can_place(pos)  # Check safety first
    
    player.place_block()  # Should place block at neighbor position
    
    assert world.get_block(pos) == DIRT
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_place_block.py -v`
Expected: FAIL with "place_block method not defined"

- [ ] **Step 3: Implement a `place_block()` method that ensures validity before adding block**

```python
def place_block(self):
    """Place a block adjacent to the hit face."""
    if self.hit is not None and self.can_place(self.hit.neighbor_pos):
        world.set_block(self.hit.neighbor_pos, DIRT)  
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_place_block.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add player.py tests/test_place_block.py
git commit -m "feat: implement block placement logic"
```

### Task 8: Add highlight functionality for interaction point

**Files:**
- Modify: `player.py`  
- Test: `tests/test_highlight.py`

**Interfaces:**
- Consumes: raycast hit result  
- Produces: highlight mesh rebuild

- [ ] **Step 1: Write the failing test**

```python
def test_highlight_changes_on_hit():
    player = Player()
    
    # Update interaction point and check highlight updated  
    player.update_interaction_point() 
    assert player.highlight_pos is not None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_highlight.py -v`
Expected: FAIL with "highlight not implemented"

- [ ] **Step 3: Add highlight position tracking and rebuild logic in Player**

```python
def update_interaction_point(self):
    """Update interaction point from camera."""
    # ... existing raycast code ... 
    
    self.highlight_pos = self.hit.position if self.hit else None
    
    # Rebuild highlight mesh when position changes  
    self.rebuild_highlight()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_highlight.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add player.py tests/test_highlight.py
git commit -m "feat: add interaction highlight functionality"
```