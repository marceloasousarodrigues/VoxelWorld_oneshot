# VoxelWorld — Autonomous Production Migration to Godot 4

## Mission

We have decided to make **Godot 4 the production engine for VoxelWorld**.

The current Python + Ursina implementation has provided a valuable prototype and a substantial amount of tested functionality. However, the long-term goal is a polished, expandable voxel game, and we do not want to continue expanding the production architecture around Ursina.

Your task is to migrate the project to Godot 4, preserving the existing gameplay requirements, validated algorithms, architecture invariants, assets, tests, and milestone knowledge wherever appropriate.

**This is an execution task, not a request for another proposal. Investigate, plan, implement, test, fix, and continue autonomously until the migration is complete or a genuine technical blocker prevents safe progress.**

Do not ask for approval between stages. The user explicitly authorises autonomous execution.

---

## 1. Mandatory Superpowers workflow

Use the repository's installed Superpowers workflow.

1. Invoke and follow the `using-superpowers` skill.
2. Apply the appropriate brainstorming, planning, systematic-debugging, implementation, code-review, and verification skills.
3. Inspect the actual repository and existing documentation before making architectural decisions.
4. Reuse completed engine evaluations and prototypes rather than repeating experiments unnecessarily.
5. Produce the required specifications and implementation plans in the repository's established documentation locations.
6. Execute the plan without stopping for routine approval.
7. Review changes, run tests, address failures, and verify actual runtime behaviour.
8. Update milestone documentation and commit completed stages according to the existing Git workflow.

Respect the installed skills' required workflow and quality gates. Reviews are internal workflow steps, not requests for the user to approve routine decisions.

Do not invent skill names or assume a skill is installed without checking.

## 2. Autonomous execution authority

The user authorises you to make reasonable technical decisions and execute the complete migration.

You may independently:

- Inspect and modify project files.
- Create branches, savepoints, modules, scenes, resources, tests, and documentation.
- Install necessary project dependencies and configure the development environment where supported.
- Select Godot APIs and architecture.
- Choose between Godot Voxel Tools and native Godot chunk meshes using evidence.
- Refactor engine-independent logic where necessary to establish clean boundaries.
- Implement and test migration stages.
- Fix bugs discovered during implementation.
- Adjust the implementation plan when evidence requires it.
- Commit coherent, validated changes following the repository's conventions.

**Do not stop to ask whether to begin implementation, whether to continue to the next milestone, or whether to fix a failure you have already identified.**

When encountering ordinary uncertainty, investigate, compare options, choose the most appropriate solution, document the rationale, and continue.

Stop only when further progress is genuinely blocked, a required resource is unavailable with no reasonable alternative, or an operation would risk irreversible loss of unrelated user work. Exhaust safe alternatives first.

Do not wait for another user message after completing a plan or an intermediate stage.

## 3. Protect the existing project

Before making changes:

- Inspect `git status`, the current branch, recent commits, and existing tags.
- Identify uncommitted changes and preserve them.
- Inspect the repository's milestone documentation, `AGENTS.md`, OpenCode agent configuration, tests, and existing engine evaluation.
- Establish an isolated migration branch or equivalent safe working area.
- Create recoverable savepoints at meaningful stages.

Never reset the repository, discard user changes, rewrite history, delete existing milestones, or perform destructive Git operations as a shortcut.

Do not modify unrelated configuration or work.

The Ursina implementation must remain available as a reference throughout the migration. Do not delete or replace it until the Godot implementation has passed the agreed production acceptance criteria.

Keep new Godot production files organised and clearly separated from the reference implementation.

## 4. Recover the project's existing state

Inspect M1–M16 and the existing M17 engine evaluation.

The known milestones include:

- M1: Coordinate utilities.
- M2: Block data.
- M3: Mesh generation.
- M4: World abstraction.
- M5: Terrain generation and chunk entities.
- M6: Player, camera, and collision.
- M7: Block interaction.
- M10–M12: Texture manifest, asset integration, atlas, and face-orientation validation.
- M13: Water storage, deterministic simulation, resumable jobs, cross-chunk propagation, mesh culling, and interaction hooks.
- M16: Infrastructure hardening, test collection health, and CI.

Verify the current repository because this list may not reflect every subsequent change.

Recover the exact status of M17 and any existing Godot prototypes, benchmarks, technical decisions, or evaluation documents.

Do not assume a previous experiment passed merely because it was planned. Inspect its implementation and evidence.

Create a migration matrix mapping existing requirements, invariants, tests, and functionality to their Godot equivalents.

Preserve the useful knowledge from every milestone, including known bugs, performance measurements, and previous implementation decisions.

## 5. Production engine decision

Godot 4 is the production target.

Ursina is the reference implementation, not the future production architecture.

Unreal Engine 5 is not the default alternative. Do not start a new Unreal evaluation unless evidence reveals a material blocker that makes the Godot approach unsuitable.

### Evaluate the voxel implementation

Investigate Godot Voxel Tools and native Godot chunk meshes.

Prefer Voxel Tools if the current compatible version supports our required editable block terrain, chunk updates, custom data, collision, streaming, and integration with our world simulation.

Choose native Godot chunk meshes if Voxel Tools imposes unacceptable constraints or unnecessary complexity.

Base the decision on repository evidence, compatibility checks, a runnable prototype, and measured results where needed.

Do not spend excessive time comparing alternatives. Resolve the decision early enough to begin production implementation.

Do not maintain two complete production renderers.

Document the chosen approach and its limitations.

## 6. Target architecture

Establish clear boundaries between logical world state, simulation, persistence, and engine-specific presentation.

The architecture must account for:

- Block definitions, identifiers, and metadata.
- World coordinates and chunk coordinates.
- Logical chunk storage.
- Terrain generation.
- Chunk loading, unloading, and streaming.
- Mesh generation and updates.
- Block visibility and face culling.
- Collision and player interaction.
- Water storage and fluid simulation.
- Inventory, hotbar, and block placement rules.
- Persistence and save/load.
- Entities and NPC simulation.
- Structures and construction.
- Enemy AI, raids, and delegated tasks.
- Rendering, materials, lighting, and input.

These systems do not all need to be implemented immediately, but their dependencies and intended interfaces must be documented.

Use Godot's scene system, resources, physics, rendering, and tooling appropriately.

Do not mechanically translate every Python class into GDScript. Preserve proven algorithms and behaviours while designing idiomatic Godot modules.

Choose GDScript or C# based on actual project requirements, available dependencies, performance needs, and maintainability. Document the choice and apply it consistently.

Prefer simple, testable boundaries over excessive abstraction.

## 7. World and chunk invariants

Preserve the existing logical-world architecture.

- Logical block and chunk data remain authoritative.
- Rendering is a representation of logical state, never the source of truth.
- Meshes can be rebuilt from logical data.
- Block edits correctly invalidate affected rendering and simulation state.
- Chunk boundaries behave consistently.
- Cross-chunk edits update all affected chunks.
- Unloaded or unavailable neighbouring chunks are handled explicitly.
- Collision and rendering updates do not corrupt world data.
- Save/load preserves the logical state.
- Rendering changes do not silently alter gameplay rules.

Keep chunk dimensions and coordinate conventions consistent with the existing project unless measured evidence justifies a documented change.

The existing implementation uses 16×16×16 chunks in relevant systems. Verify the current convention and preserve it where applicable.

Use efficient chunk rendering rather than one engine object per block.

## 8. Preserve the water simulation

M13 represents substantial existing work and must not be casually rewritten.

Preserve the established behaviour, including:

- Water storage and block-level water state.
- Deterministic propagation rules.
- Vertical movement priority.
- The established maximum horizontal spread.
- Resumable simulation jobs and bounded processing budgets.
- Version-based invalidation when edits occur during simulation.
- Atomic commits.
- Cross-chunk propagation.
- Mesh culling and water surface updates.
- Terrain water sources.
- Player interaction integration.

The existing implementation includes a maximum spread of seven and resumable processing controlled by a per-tick work budget. Verify the current source and tests before porting the exact constants.

Separate simulation correctness from rendering.

The Godot implementation must not depend on visible mesh geometry to determine the logical water state.

Port and adapt the algorithm deliberately. Do not simplify away determinism, invalidation guarantees, or established rules merely to get a visual result quickly.

Add regression tests for the ported behaviour.

## 9. Texture assets and visual quality

The goal is a coherent, polished voxel world, not a technical demo of coloured cubes.

Reuse the existing texture manifest and validated assets where appropriate.

Inspect the current texture pipeline, including:

- Texture selection per block and face.
- Atlas generation and coordinates.
- UV mapping and orientation.
- Transparency.
- Filtering and mipmapping.
- Material settings.
- Lighting and normals.
- Texture scale and repetition.
- Chunk-boundary seams and face culling.

Correct existing asset or mapping problems at their actual source.

Do not carry forward Ursina-specific rendering workarounds blindly.

Prefer a maintainable Godot material and texture pipeline with consistent visual results.

Use external assets or dependencies only when they materially improve the game and are compatible with their licences. Do not spend the migration collecting assets before the renderer is functional.

## 10. Migration stages

Execute the stages below in dependency order. Continue automatically when a stage passes its acceptance criteria.

### Stage A — Repository audit and migration preparation

- Inspect the current codebase and M17 findings.
- Map existing systems, tests, invariants, and dependencies.
- Establish the migration branch and savepoints.
- Record the engine decision.
- Create the migration specification and staged plan.
- Identify risks and measurable acceptance criteria.

Do not stop after documenting the plan.

### Stage B — Godot production foundation

- Establish a working Godot 4 project.
- Configure the project, source structure, dependencies, logging, and validation workflow.
- Establish the world-data and rendering boundaries.
- Set up automated tests and a reproducible launch procedure.
- Verify the project opens, builds or runs, and can be tested automatically.

### Stage C — Playable voxel vertical slice

Implement:

- Deterministic coordinate and chunk utilities.
- Block definitions and logical chunk storage.
- Basic terrain generation.
- Efficient chunk mesh generation and rendering.
- Correct materials and face orientation.
- First-person player movement.
- Camera controls and collision.
- Block targeting.
- Block breaking and placement.
- Basic interaction feedback and hotbar integration where feasible.

Acceptance requires an actual playable Godot scene with coherent terrain, correct block interactions, and no fundamental chunk-boundary defects.

### Stage D — World updates and streaming

Implement:

- Dirty-chunk tracking.
- Correct mesh rebuilding after edits.
- Neighbouring-chunk invalidation.
- Chunk loading and unloading.
- World-coordinate and chunk-coordinate correctness.
- Efficient collision updates.
- Appropriate scheduling to prevent large frame stalls.

Verify movement across chunk boundaries and repeated loading and unloading.

### Stage E — Water simulation and persistence

Port the established water rules and integrate them with the Godot world model.

Implement and validate:

- Water state storage.
- Simulation scheduling and bounded processing.
- Cross-chunk propagation.
- Version invalidation and atomic updates.
- Water rendering and mesh culling.
- Block interaction with water.
- World persistence and save/load.

Test deterministic outcomes, edits during active simulation, chunk boundaries, and restoration after loading a saved world.

### Stage F — Visual quality and day/night cycle

Implement and verify:

- Consistent texture assignments and scale.
- Correct face UVs.
- Materials and lighting.
- Day/night transitions.
- Suitable environmental illumination and shadows.
- Water appearance.
- Visual consistency at normal gameplay distances.

Capture before-and-after screenshots where possible.

Do not sacrifice stable performance for unnecessary effects.

### Stage G — Performance and world scalability

Establish reproducible benchmarks and compare them with the existing reference implementation where a fair comparison is possible.

Measure:

- Frame-time percentiles.
- Worst observed frame stalls.
- Chunk generation throughput.
- Chunk mesh rebuild time.
- Memory usage during exploration.
- Collision update costs.
- Water simulation processing costs.
- Streaming behaviour and resource cleanup.

Record hardware, engine version, world configuration, test duration, and measurement methodology.

Investigate bottlenecks before introducing optimisations. Do not claim Godot solves the existing stuttering problem without evidence.

### Stage H — Future gameplay foundation

Establish the architecture needed for:

- Structures and building systems.
- Large settlements.
- Resident NPCs.
- NPC task assignment and delegation.
- Resource gathering and production.
- Enemy behaviour and raids.
- Persistent world entities.

Keep these systems separate from rendering and chunk implementation.

Implement only the foundations necessary to support future development. Do not derail the migration by building the complete NPC or city simulation before the core world is stable.

### Stage I — Production readiness

- Run the complete relevant test suite.
- Verify a clean Godot launch and build.
- Test core gameplay in the actual runtime.
- Verify chunk boundaries, water, interactions, and persistence.
- Confirm that the migration did not alter the reference implementation.
- Run the agreed performance tests.
- Review dependencies, licensing, and deployment requirements.
- Update milestone documentation and migration records.
- Commit coherent, validated changes.
- Produce a final report of completed work, measurements, remaining limitations, and the state of the repository.

Do not remove the Ursina reference implementation as part of this stage unless all migration acceptance criteria are met and removal is explicitly covered by a safe, documented finalisation step.

## 11. Testing and quality gates

Reuse existing tests and specifications as the behavioural contract.

Create equivalent Godot-side tests for critical behaviour where practical.

Cover at minimum:

- Coordinate conversion and chunk indexing.
- Block definitions and state transitions.
- Terrain generation determinism.
- Mesh generation and face orientation.
- Chunk-boundary updates.
- Block breaking and placement.
- Collision and player movement.
- Water propagation and invalidation.
- Save/load correctness.
- Chunk streaming and lifecycle.
- Performance regression checks.

Run tests after each meaningful change.

When a test fails, diagnose and fix the underlying problem before proceeding. Do not disable, weaken, skip, or delete tests merely to obtain a passing suite.

Distinguish automated test results from manual runtime verification.

A successful code review or project import is not proof that gameplay works.

## 12. Autonomous Git and recovery strategy

Use the existing repository's conventions.

- Keep the migration isolated.
- Create savepoints before significant architectural changes.
- Commit coherent units of validated work.
- Include meaningful commit messages.
- Maintain a recoverable state between stages.
- Preserve unrelated user changes.
- Do not force-push, rewrite history, or destroy existing branches or tags.

Inspect the final working tree and commit history before reporting completion.

## 13. Definition of done

The migration is complete only when:

1. Godot 4 is the working production implementation.
2. The project launches and runs as an actual game.
3. The player can explore generated voxel terrain.
4. Movement and collision work correctly.
5. Block targeting, breaking, and placement work.
6. Chunk rendering and updates behave correctly across boundaries.
7. The established water simulation behaviour is preserved and tested.
8. Persistence and save/load work for the implemented world state.
9. Visuals are coherent and the day/night implementation works if completed as part of the migration.
10. The relevant test suite passes.
11. Runtime verification has been performed and documented.
12. Performance has been measured rather than assumed.
13. Existing Ursina work and unrelated changes remain preserved.
14. Documentation accurately identifies completed and remaining work.

If a criterion cannot be completed because of a genuine blocker, document the exact failure, the evidence, the attempted alternatives, and the remaining work. Do not falsely declare completion.

## 14. Final execution instruction

**Begin now.**

Inspect the repository, recover the existing M17 findings, invoke the required Superpowers skills, establish a safe migration workspace, and execute the migration in stages.

Do not stop after writing the specification or plan.

Do not ask for approval at stage boundaries.

Make reasonable decisions independently, implement them, test them, fix failures, and proceed automatically.

Keep the project recoverable and report progress through repository documentation and coherent commits.

**Godot 4 is the production target. Ursina is the reference implementation. Preserve proven behaviour and keep working until the production migration is complete or a genuine blocker prevents safe progress.**