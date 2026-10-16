# VoxelWorld — Autonomous Godot Development Mission

## 1. Mission and expected outcome

You are the autonomous development team responsible for turning **VoxelWorld**, an existing Minecraft-like voxel game, into a substantial, playable 3D game using **Godot 4**.

Work directly in the actual Windows development environment and the existing repository. Use the available tools, agents, terminal, Git, installed engines, and resources.

**Your priority is implementation, not planning. Build a playable game as early as possible and continue improving it for the entire available session.**

Do not stop after:
- Inspecting the repository.
- Producing an environment report.
- Writing specifications or plans.
- Creating empty project scaffolding.
- Implementing a minimal proof of concept.
- Reporting that the next milestone is ready to begin.

Continue through implementation, execution, testing, debugging, visual inspection, performance optimization, and further gameplay development.

The final objective is a coherent, increasingly complete Minecraft-like game with a large explorable world, building, survival systems, creatures, and the foundations for settlements and NPCs.

Work autonomously until the available session ends or a genuine blocker prevents further progress. If interrupted, leave a reliable recovery point so the work can resume.

## 2. Mandatory execution priority

Follow this order:

1. Inspect the real Windows environment and the current repository.
2. Recover the existing M17 work and its shared scenario, contracts, and results.
3. Verify the installed Godot version and whether the project can run.
4. Verify whether Zylann Voxel Tools is compatible with the installed Godot version.
5. Create or complete the Godot project in the isolated M17 directory.
6. Build and run a playable 3D voxel slice immediately.
7. Validate terrain generation, player movement, collision, block breaking, and block placement.
8. Continue expanding the playable game without waiting for another approval.
9. Test and optimize continuously.
10. Finish each work session with a Git savepoint and an updated progress/resume document.

**Do not spend the session repeatedly evaluating engines. Godot 4 is the selected engine.**

Try Voxel Tools if compatibility and integration are straightforward. If it is unavailable, incompatible, or creates disproportionate integration risk, move promptly to a native Godot implementation using chunk meshes and custom voxel data structures. Do not let plugin research block implementation.

If Godot is missing, investigate a safe, reproducible installation or portable setup. Use official sources and continue where possible. Do not silently abandon the project because the environment differs from expectations.

## 3. Inspect the existing project before changing anything

Inspect:
- Repository structure and Git status.
- `AGENTS.md` and any relevant project-specific agent instructions.
- Existing milestone documentation and M17 files.
- Existing Superpowers skills and configured Plan, Builder, Tester, and Reviewer agents.
- The existing Ursina implementation and its architecture.
- Available Python and Godot versions, dependencies, GPU, and runtime capabilities.
- Existing tests, fixtures, contracts, performance reports, and visual assets.

Read the existing M17 documents, including those under:

- `prototypes/m17/results/environment-preflight.md`
- `prototypes/m17/results/feasibility-checkpoint.md`

Also inspect the shared M17 scenario and fixture files to establish their actual paths and contracts.

The previous cloud preflight was blocked because that environment lacked installed game engines and graphics capabilities. **Do not assume that report describes this Windows machine.** Check the real environment.

Use existing work where useful. Do not recreate files unnecessarily or overwrite valid results just to follow a new workflow.

If an existing file differs from the expected path, locate the real file rather than assuming it is missing.

## 4. Project boundaries and preservation rules

The existing production game is written in Python using Ursina and has completed milestones M1–M16.

The Godot implementation is a new engine direction. Keep it isolated initially under:

`prototypes/m17/godot/`

Keep shared M17 contracts, fixtures, documentation, and results under the existing `prototypes/m17/` structure.

Rules:
- Preserve the production Ursina game as a reference and fallback.
- Do not rewrite or migrate production Ursina files as part of the initial Godot implementation.
- Do not delete existing project assets, tests, documentation, or milestone work.
- Do not overwrite unrelated user changes.
- Inspect Git status before modifying files.
- Do not discard, reset, or clean changes that you did not create.
- Keep Godot-specific dependencies and assets inside the project where practical.
- Use small, coherent, reversible changes.
- Maintain a working Git branch or the repository's existing branch convention.
- Commit meaningful working states when safe.
- Never commit secrets, credentials, local machine-specific configuration, or unnecessary generated files.

If the working tree contains unrelated changes, preserve them. Do not treat a dirty working tree as permission to remove those changes.

Before a risky operation, establish a recoverable savepoint.

## 5. Autonomous operation and approvals

You are authorized to make routine engineering decisions without asking me to approve every step.

Use the available Superpowers workflow and configured agents when they are useful:
- Plan the next concrete implementation increment.
- Delegate implementation to the Builder.
- Use the Tester to validate behavior.
- Use the Reviewer to identify defects and architectural risks.

Adapt the workflow to the existing repository configuration. Do not waste time installing an entire agent ecosystem if equivalent tools already exist.

Do not stop to request approval for ordinary decisions involving:
- Internal code architecture.
- File organization within the project boundary.
- Local development dependencies.
- Openly licensed textures, models, audio, and other assets.
- Routine bug fixes and refactoring.
- Tests, profiling, and local builds.
- Reversible performance improvements.
- Normal Git savepoints.

When blocked, investigate alternatives and continue with the best safe option.

Ask for assistance only when a decision genuinely requires user authorization, credentials, paid purchases, a subscription, a destructive action, or an external action with meaningful consequences.

Never claim to have installed, executed, tested, rendered, or verified something unless the relevant action actually succeeded.

## 6. Resource and asset acquisition

You have explicit authorization to download resources needed to develop and improve the game, including:
- Texture packs and individual textures.
- Open-source repositories and Godot plugins.
- Compatible voxel tools and supporting libraries.
- 3D models and vegetation assets.
- Creature and character models.
- Sound effects, ambient audio, and music.
- Particle effects, shaders, materials, and other suitable assets.
- Documentation and examples needed for integration.

Do not restrict the game to procedural-only assets. Use procedural generation where appropriate, but acquire good external assets when they materially improve the result.

Prefer:
1. Official project repositories and documentation.
2. Reputable open-source projects.
3. Clearly licensed assets from established asset libraries.
4. Free resources with explicit permission for the intended use.

For each external resource:
- Verify its source and intended use.
- Record the asset or package name, source URL, license, attribution requirements, and local destination.
- Keep a project-level asset manifest, for example `prototypes/m17/godot/ASSET_MANIFEST.md`.
- Include required attribution and license files.
- Respect redistribution and modification restrictions.
- Avoid downloading duplicate or unnecessary assets.
- Avoid executing unknown binaries or scripts from untrusted sources.

Do not pirate paid assets, bypass license restrictions, or purchase anything or subscribe to a service without explicit authorization.

Do not introduce a large dependency merely because it exists. Evaluate compatibility, maintenance, license, performance, and actual project needs.

If a preferred asset or plugin is unavailable, use another suitable source or implement a reasonable alternative.

## 7. Technical architecture

Build a robust, extensible voxel architecture rather than a collection of unrelated demo scripts.

Use these as the initial architectural requirements, adapting only when there is a clear technical reason.

### 7.1 World and chunk representation

- Initial chunk dimensions: 16 × 16 × 16 blocks.
- Logical voxel data is authoritative.
- Rendered chunk meshes are derived data.
- Do not create one engine object per voxel.
- Generate chunk meshes efficiently, preferably merging visible faces and avoiding internal faces.
- Use appropriate collision representations rather than individual collision objects for every block.
- Support chunk coordinates and world coordinates correctly.
- Use floor-based coordinate conversion so negative world coordinates behave correctly.
- Handle edits on chunk boundaries.
- Invalidate and rebuild affected meshes when a block changes.
- Avoid rebuilding unrelated chunks.
- Keep logical state separate from rendering state.
- Design data structures so larger worlds and background generation can be supported.

### 7.2 Initial block types

Support at least:
- AIR
- GRASS
- DIRT
- STONE
- WATER

Keep block definitions centralized, with extensible material, collision, transparency, and interaction properties.

Do not assume water should behave like a normal solid cube.

### 7.3 Procedural world generation

Implement deterministic terrain generation using a configurable seed.

The shared M17 scenario uses seed `17015`. Preserve the existing shared fixture and contract unless inspection reveals a concrete incompatibility.

Generate useful terrain with:
- Surface height variation.
- Grass, dirt, and stone layers.
- Water sources and terrain features.
- Distinct regions or biomes.
- Vegetation and trees.
- Caves and underground areas.
- Landmarks and interesting exploration opportunities.

Prioritize correctness, performance, and visual coherence. Extend the generator incrementally rather than producing an enormous, untestable generation system at once.

### 7.4 Player and interaction

Implement:
- First-person camera.
- Mouse look.
- WASD movement.
- Jumping and gravity.
- Collision with the world.
- Sensible movement and camera settings.
- Block targeting using a raycast or equivalent reliable voxel traversal.
- Left-click block breaking.
- Right-click block placement.
- Placement against the targeted face.
- Prevention of placement inside the player.
- Correct world and chunk boundary behavior.
- Updates to logical data, meshes, and collision after edits.

Ensure the basic loop works in the running game, not only in unit tests.

### 7.5 Rendering and visual quality

Visual quality is a major objective, alongside performance and world size.

Develop a coherent visual presentation:
- Good texture mapping and face orientation.
- Consistent block scale.
- Suitable terrain materials.
- Attractive sky and fog.
- Directional lighting.
- Shadows where performant.
- Water with appropriate transparency, color, depth cues, and surface appearance.
- Vegetation and terrain variation.
- Clear environmental silhouettes.
- Suitable ambient effects and particles.
- Smooth transitions where appropriate.

Use real assets when licensed and technically appropriate. Avoid the appearance of a bare debugging scene once the basic renderer works.

Keep performance in mind when selecting shaders, shadow settings, textures, geometry density, and effects.

Do not claim that a visual issue is fixed without inspecting a running build or a reliable rendered capture.

### 7.6 World streaming and persistence

Implement:
- Loading chunks near the player.
- Unloading distant chunks when safe.
- A configurable render distance.
- Bounded generation and mesh-building work per frame.
- Safe handling of chunk boundaries during streaming.
- Persistent player edits.
- World save and load.
- A versioned save format or a clear migration strategy.
- Recovery from incomplete or invalid save data where practical.

Use asynchronous or staged processing when it improves responsiveness, while keeping logical world state consistent.

Avoid loading the entire world into memory unnecessarily.

### 7.7 Water behavior

Implement water as a distinct system, not merely a blue block.

Investigate and reuse the existing Ursina M13 water design where relevant, including its deterministic solver, cross-chunk propagation, edit invalidation, and bounded per-tick processing.

Preserve the useful behavioral principles:
- Water has logical state independent of its rendered surface.
- Vertical movement should be prioritized appropriately.
- Horizontal spreading should have a defined limit.
- Cross-chunk propagation must work.
- Meshes must correctly handle water surfaces and neighboring blocks.
- Simulation work must be bounded.
- Changes must be committed consistently.
- Water edits must not leave stale simulation jobs corrupting newer state.

Adapt the implementation to Godot rather than blindly copying engine-specific code.

## 8. Continue expanding into a real game

Once the playable voxel foundation is stable, keep implementing the following systems. Do not stop at block placement.

### Phase A — Core playable world
- World generation.
- Chunk meshes and streaming.
- Player movement and collision.
- Block breaking and placement.
- Correct negative coordinates and chunk boundaries.
- Water rendering and behavior.
- Textures, lighting, and basic environmental polish.
- World save/load.
- Main menu and a usable play loop.

### Phase B — Building and survival
- Inventory data model.
- Visible hotbar and selection.
- Inventory interface.
- Collecting and placing items.
- Crafting recipes and crafting interface.
- Tools and tool durability where appropriate.
- Health and damage.
- Survival settings, including hunger if it fits the design.
- Environmental and combat feedback.
- Death and respawn behavior.
- Configuration and pause menus.

### Phase C — Living world
- Passive creatures.
- Hostile creatures.
- Basic creature navigation and AI.
- Combat and loot.
- Spawn rules and despawning.
- Day/night cycle.
- Weather or environmental variation if practical.
- Vegetation, resources, caves, and exploration incentives.

### Phase D — Structures and settlements
- Procedural structures.
- Player construction beyond simple isolated blocks.
- Reusable structure definitions.
- NPC foundations with persistent identity and state.
- NPC movement and basic tasks.
- Settlement layout and resident assignment.
- Resource storage and task delegation.
- Basic defensive behavior and enemy raids.
- A foundation for city management and larger settlement systems.

Implement these in dependency order. Prefer complete, testable gameplay loops over disconnected feature stubs.

If the available session is limited, maximize the amount of working, integrated gameplay and leave the remaining features clearly tracked in the roadmap. Do not pretend unimplemented systems exist.

## 9. Performance and scalability

The game is intended to support a large explorable world, not just a small test map.

Use profiling and measurements to guide decisions.

Pay attention to:
- Chunk generation latency.
- Mesh construction and upload costs.
- Frame-time spikes when crossing chunk boundaries.
- Memory use.
- Garbage collection or allocation pressure where relevant.
- Collision generation and updates.
- Water simulation cost.
- Streaming queue growth.
- Rendering cost, overdraw, shadows, and transparency.
- Save/load latency.
- Repeated work that can be cached or avoided.

The existing Ursina project previously exhibited chunk-boundary stalls and significant garbage-collection pauses. Treat those as useful historical warnings, not proof that the same problems exist in Godot.

Do not invent performance measurements. Record the hardware, engine version, test setup, observed values, and limitations.

Optimize actual bottlenecks without compromising correctness. Do not prematurely build an unnecessarily complex multithreading architecture.

Use a repeatable seed and workload for performance comparisons where possible.

## 10. Testing and verification

Testing must accompany implementation.

### Automated tests

Create or extend tests for:
- Coordinate conversion, including negative coordinates.
- Chunk indexing and boundaries.
- Block storage and block definitions.
- Deterministic generation.
- Mesh visibility and face culling.
- Cross-chunk mesh invalidation.
- Breaking and placing blocks.
- Player-placement safety.
- Water rules and cross-chunk behavior.
- Streaming and unloading.
- Persistence and edited-world recovery.
- Inventory and crafting rules.
- NPC state and other gameplay systems as they are implemented.

Use the existing shared M17 fixtures and contracts. Keep shared tests engine-independent where appropriate and add Godot-specific tests for engine integration.

### Runtime verification

Run the actual Godot project.

Verify, where tooling allows:
- The project imports without errors.
- The project starts.
- The player can move and look around.
- Terrain is generated and rendered.
- Collision works.
- Blocks can be broken and placed.
- Chunk boundaries behave correctly.
- Water is visible and behaves as designed.
- Save/load preserves edits.
- No recurring runtime errors occur.
- Performance remains acceptable as the player explores.

Capture screenshots or recordings where possible. Inspect them rather than merely confirming that a file exists.

Use headless tests for what can be tested headlessly, but do not treat a successful headless run as proof that the rendered game works.

When a test fails:
1. Read the full error.
2. Identify the root cause.
3. Fix it.
4. Rerun the relevant test.
5. Rerun broader tests when appropriate.

If the same approach fails twice, reassess the approach instead of repeating it indefinitely.

Do not claim a feature is complete merely because its script exists.

## 11. Git savepoints and recovery

Create meaningful Git savepoints throughout development.

Before major changes:
- Inspect `git status`.
- Preserve existing work.
- Establish a recoverable state if appropriate.

After meaningful increments:
- Run relevant tests.
- Review the diff.
- Commit coherent changes when safe.
- Record the commit hash and test results.

Do not create enormous commits containing unrelated changes. Do not commit generated build outputs unless the project explicitly requires them.

If Git configuration or repository permissions prevent committing, preserve the files and document the limitation. Never rewrite history or discard user work merely to make the repository look clean.

## 12. Persistent progress and resume protocol

Maintain a persistent status file under the M17 directory, for example:

`prototypes/m17/results/godot-progress.md`

Update it frequently and before the session ends.

Record:
- Current overall objective.
- Current phase and next concrete task.
- What has actually been implemented.
- Files and important architectural decisions.
- Current Git branch and latest savepoint commit.
- Godot version and relevant dependency versions.
- Commands used to build and run the project.
- Tests run and their actual results.
- Whether the game was launched and visually inspected.
- Known defects and current blockers.
- Asset sources and licensing status.
- Performance measurements, if available.
- The exact command or action to resume work.

Also maintain an actionable roadmap, such as:

`prototypes/m17/results/godot-roadmap.md`

Use checkboxes and distinguish:
- Implemented and verified.
- Implemented but not verified.
- In progress.
- Not started.
- Blocked.

Do not mark tasks complete based only on intention or code generation.

If you are interrupted or approach the session limit, finish with:
1. A recoverable Git savepoint when possible.
2. Updated progress and roadmap documents.
3. A concise handoff describing the next exact action.

On resumption, read these documents and inspect the real repository state before continuing. Do not restart from the beginning or repeat completed work unnecessarily.

## 13. Work loop

Use this cycle continuously:

1. Select the highest-value unfinished task.
2. Define a small, concrete acceptance criterion.
3. Implement it.
4. Run the relevant tests.
5. Launch or inspect the game when relevant.
6. Fix failures and regressions.
7. Review the diff and architectural impact.
8. Commit a savepoint when appropriate.
9. Update progress and roadmap.
10. Immediately begin the next task.

Do not end a work cycle by merely suggesting the next task. Start it, unless a genuine blocker or session limit prevents you.

Prioritize a stable, playable foundation before broadening the scope. After the foundation is stable, continue implementing the next integrated gameplay system.

## 14. Definition of success

Success is measured by demonstrable progress toward a real game, not by the volume of documentation produced.

The immediate success criteria are:
- A Godot project that actually opens and runs.
- A generated 3D voxel world.
- A controllable first-person player.
- Working collision.
- Functional block breaking and placement.
- Correct chunk and coordinate behavior.
- A credible visual foundation.
- Automated tests and runtime verification.
- Recoverable Git savepoints.
- Persistent progress documentation.

The longer-term objective is a polished, extensible voxel survival and building game with a large world, meaningful exploration, water, inventory, crafting, creatures, structures, and increasingly capable NPC settlements.

**Start now. Inspect the actual Windows environment and repository, recover existing M17 work, and then build and run the first playable Godot version. Do not stop at preflight, feasibility analysis, planning, or documentation. Keep implementing, testing, fixing, and expanding the game until the available session ends or a genuine blocker prevents further progress.**