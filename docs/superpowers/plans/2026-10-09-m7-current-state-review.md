# M7 Block Interaction Implementation Status Review

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the M7 Block Interaction milestone with all implemented functionality including actual block breaking and placement logic using raycasting system.

**Architecture:** Implementation follows existing architectural patterns for world, player, and interaction management.

**Tech Stack:** Python 3.8+, Pygame/ursina framework

**Spec:** docs/superpowers/specs/2026-10-08-m7-block-interaction-design.md

## Global Constraints

- Player interaction must integrate with raycast functionality
- Block breaking logic must check if block exists before removing it
- Block placement logic must consider neighbor positions and avoid placing inside player
- All operations must mark chunks as dirty to trigger mesh regeneration
- Visual highlight system must show valid placement points

## Review Focus

- Raycasting implementation completeness
- Actual block modification operations vs. just interaction state update
- Integration points between raycast, player input, world modification 
- Proper handling of chunk dirty tracking and refresh for neighbor chunks
- Valid placement area checking to avoid placing inside player

---

### Task 3: Complete Chunk.refresh functionality

**Files:**
- Modify: `chunk.py`

**Interfaces:**
- Consumes: 
- Produces: 

- [ ] **Step 1: Write the failing test**
```python
def test_chunk_refresh_mesh_rebuild():
    # Test that refresh properly rebuilds mesh with neighbor visibility
    chunk = Chunk(0, 0, 0)
    chunk.set_block(0, 0, 0, 1)  # Set a block 
    chunk.refresh()  # Should rebuild mesh
    # Verify mesh was rebuilt
```

- [ ] **Step 2: Run test to verify it fails**
Run: `pytest tests/test_chunk_refresh.py -v`
Expected: FAIL with "function not implemented"

- [ ] **Step 3: Implement `refresh()` in `chunk.py`**

The refresh method should properly rebuild the mesh and handle neighbor visibility information.

- [ ] **Step 4: Run test to verify it passes**
Run: `pytest tests/test_chunk_refresh.py -v`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add chunk.py tests/test_chunk_refresh.py
git commit -m "feat(chunk): implement proper mesh rebuild in refresh"
```

### Task 4: Complete raycasting implementation

**Files:**
- Modify: `raycast.py`

**Interfaces:**
- Consumes: World.get_block  
- Produces: Raycasting results with position, block type, and hit face

- [ ] **Step 1: Write the failing test**
```python
def test_raycast_with_hit():
    # Test raycasting against a solid block
    world = World()
    world.set_block(10, 10, 10, 1)  # Place a block 
    result = raycast((0, 0, 0), (1, 0, 0), world)
    assert result is not None
    assert result['position'] == (10, 10, 10)
```

- [ ] **Step 2: Run test to verify it fails**
Run: `pytest tests/test_raycasting.py -v`
Expected: FAIL with "function not implemented"

- [ ] **Step 3: Implement raycasting function in `raycast.py`**

The raycasting should implement the correct DDA algorithm and correctly identify block faces.

- [ ] **Step 4: Run test to verify it passes**
Run: `pytest tests/test_raycasting.py -v`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add raycast.py tests/test_raycasting.py
git commit -m "feat(raycast): complete DDA algorithm with proper face detection"
```

### Task 5: Complete player interaction state handling

**Files:**
- Modify: `player.py`

**Interfaces:**
- Consumes: raycast() function, World.set_block(), World.get_block()
- Produces: Player state updates and interaction events

- [ ] **Step 1: Write the failing test**
```python
def test_player_left_button_break():
    # Test that left click breaks a block
    player = VoxelPlayer(world)
    result = player._update_interaction()  
    # Verify that breaking logic is called with correct parameters
```

- [ ] **Step 2: Run test to verify it fails**
Run: `pytest tests/test_player_interaction.py -v`
Expected: FAIL with "interaction not implemented"

- [ ] **Step 3: Implement actual block breaking in player interaction**

Player needs methods for actually removing blocks when left-clicked.

- [ ] **Step 4: Run test to verify it passes**
Run: `pytest tests/test_player_interaction.py -v`  
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add player.py tests/test_player_interaction.py
git commit -m "feat(player): implement actual block breaking via interaction"
```

### Task 6: Implement block breaking functionality  

**Files:**
- Modify: `player.py`, `world.py`

**Interfaces:**
- Consumes: `World.get_block()`, `World.set_block()`, player interaction state
- Produces: World modifications and chunk dirty tracking

- [ ] **Step 1: Write the failing test**
```python
def test_player_break_block():
    world = World()
    world.set_block(10, 10, 10, 1)  # Place a block
    player = VoxelPlayer(world)
    
    # Simulate breaking action - this should remove block and mark chunk dirty
    # Verify the block is removed and chunk is marked as dirty
```

- [ ] **Step 2: Run test to verify it fails**
Run: `pytest tests/test_break_block.py -v`
Expected: FAIL with "function not implemented"

- [ ] **Step 3: Implement actual block breaking function**

Implement break_block method that calls world.set_block() and triggers dirty tracking.

- [ ] **Step 4: Run test to verify it passes**
Run: `pytest tests/test_break_block.py -v`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add player.py world.py tests/test_break_block.py
git commit -m "feat(world): implement block breaking with proper dirty tracking"
```

### Task 7: Implement block placement functionality

**Files:**
- Modify: `player.py`, `world.py` 

**Interfaces:**
- Consumes: World.get_block(), World.set_block(), player interaction state, raycast
- Produces: Actual world modification for placing blocks

- [ ] **Step 1: Write the failing test**
```python
def test_player_place_block():
    world = World()
    player = VoxelPlayer(world)
    
    # Simulate placing a block - should validate position and place block
    # Verify that block is placed at correct neighbor location
```

- [ ] **Step 2: Run test to verify it fails**
Run: `pytest tests/test_place_block.py -v`
Expected: FAIL with "function not implemented"

- [ ] **Step 3: Implement place_block() function**

Implement placement logic considering hit position and neighbor blocks.

- [ ] **Step 4: Run test to verify it passes**
Run: `pytest tests/test_place_block.py -v` 
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add player.py world.py tests/test_place_block.py
git commit -m "feat(world): implement block placement with neighbor validation"
```

### Task 8: Implement visual block highlighting  

**Files:**
- Modify: `player.py`, `chunk_entity.py` (if needed)

**Interfaces:**
- Consumes: Player interaction state, raycast results, world.get_block()
- Produces: Visual highlight feedback for valid placement positions

- [ ] **Step 1: Write the failing test**
```python
def test_player_visual_highlight():
    world = World() 
    player = VoxelPlayer(world)
    
    # Test that visual highlighting is performed when hovering over valid blocks
    # Verify highlight entity is created and positioned correctly
```

- [ ] **Step 2: Run test to verify it fails**
Run: `pytest tests/test_highlight.py -v`
Expected: FAIL with "function not implemented"

- [ ] **Step 3: Implement visual highlighting system**

Create or modify highlight visualization that shows valid placement points.

- [ ] **Step 4: Run test to verify it passes**
Run: `pytest tests/test_highlight.py -v`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add player.py chunk_entity.py tests/test_highlight.py  
git commit -m "feat(player): implement visual block highlighting"
```