# VoxelWorld

VoxelWorld's canonical game project is the native Godot project in [`godot/`](godot/).
Open that folder in Godot 4, or run the project with `--path godot` from this repository.

The earlier Python + Ursina implementation is retained under [`archive/ursina/`](archive/ursina/)
for reference. It is deprecated and is not the active game. Its tests, scripts, Python
dependencies, configuration, and original texture collection are archived there as well.

## Current status

See [`PROJECT_STATUS.md`](PROJECT_STATUS.md) for the active engine, source revision, and
latest milestone status. M37 forest composition is **partial**: the clearings and canopy
spacing improved, while a continuous tree line remains visible in the normal gameplay view.

## Run and validate

From the repository root, use a Godot 4 executable:

```powershell
godot --path godot
godot --headless --path godot --script res://scripts/tests/run_tests.gd
```

The project is GDScript-only and has no Godot plugin or native build dependency. See
[`prototypes/m17/README.md`](prototypes/m17/README.md) for controls, evidence, and the
development-machine details recorded by the project.

## Project records

- [`MILESTONES.md`](MILESTONES.md) retains the full historical milestone record.
- [`prototypes/m17/results/`](prototypes/m17/results/) retains Godot reports, measurements,
  plans, and visual evidence.
- [`docs/`](docs/) retains design specifications and implementation plans.
