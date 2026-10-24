# M17 native Godot game

A first-person voxel game built on Godot 4 with a native chunk-mesh renderer: the
project directory `godot/` holds the engine, the game and the tests,
and `prototypes/m17/shared/` holds the shared deterministic fixture and scenario.

It is a real, playable game — generated terrain, streaming, water, block breaking and
placement, inventory hotbar, menus and versioned saves — and it is still an
**early** implementation of the mission in `prototypes/m17/GODOT_MISSION.md`:
survival systems, creatures and settlements are not implemented yet.

Current state, evidence, measurements and the exact resume command live in:

- `prototypes/m17/results/godot-progress.md` — what works, what was verified, how to run it
- `prototypes/m17/results/godot-roadmap.md` — phase-by-phase checklist (A → D)
- `godot/ASSET_MANIFEST.md` — texture/asset provenance and licences

## Verified development machine

- Windows 11 Pro, build 26200, x64.
- Godot Engine `4.7.2.stable.mono.official.ed1daf0bf`, installed at `C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe`.
- NVIDIA GeForce RTX 3080; Vulkan reports NVIDIA driver `617.14.0.0` and Vulkan API `1.4.351`.
- Intel Core i7-10700K, 8 cores / 16 logical processors, 32 GB RAM; 1920×1080 display.
- Native Godot Forward+. No plugin, GDExtension or C++ toolchain is used: Zylann Voxel
  Tools was evaluated and rejected (see the progress document), so the voxel engine is
  GDScript-only and the project needs no build step.

## Setup and launch (PowerShell)

From the repository root, regenerate the deterministic fixture with only Python's
standard library (optional: the fixture is committed):

```powershell
python prototypes/m17/shared/generate_fixture.py
```

Run the game:

```powershell
& 'C:\Godot\...\Godot_v4.7.2-stable_mono_win64.exe' --path godot
```

Run the automated tests (headless; the exit code is the result):

```powershell
& 'C:\Godot\...\Godot_v4.7.2-stable_mono_win64.exe' --headless --path godot --script res://scripts/tests/run_tests.gd
```

Measure frame times (windowed; one scripted activity per run, JSON report in `results/godot/`):

```powershell
& 'C:\Godot\...\Godot_v4.7.2-stable_mono_win64.exe' --path godot --script res://scripts/tests/run_perf.gd -- --straight-to-game --seed=17017 --scenario=walk --label=perf-walk
```

The `...` is a recorded local machine path, not a portable one; set `$godot` to
another Godot 4.7.2 executable location if needed.

Capture the M41b visual-acceptance sequence (first-person pickaxe/axe/shovel/
sword, third-person idle/walk/jump/swing/sword) on the existing visual-test arena
(offscreen viewport frames, not a human desktop recording):

```powershell
& 'C:\Godot\...\Godot_v4.7.2-stable_mono_win64.exe' --path godot --script res://scripts/tests/run_camera_demo.gd
```

The M41b evidence is written as `m41b-demo-*.png` with
`m41b-demo-manifest.json`; the older M41 sequence used `m41-demo-*.png`.

Capture the M41c hand/tool visual-acceptance sequence (pickaxe idle, nearby
block, walking, swing and pavilion shade, then axe/shovel/sword and a
third-person frame):

```powershell
& 'C:\Godot\...\Godot_v4.7.2-stable_mono_win64.exe' --path godot --script res://scripts/tests/run_m41c_demo.gd
```

The M41c evidence is written as `m41c-demo-*.png` with
`m41c-demo-manifest.json`. A supplementary studio render of the four models for
construction inspection (not gameplay evidence) is produced by:

```powershell
& 'C:\Godot\...\Godot_v4.7.2-stable_mono_win64.exe' --path godot --script res://scripts/tests/run_tool_preview.gd
```

## Controls

- **WASD** move · **Space** jump · **Shift** sprint · **mouse** look.
- **Left mouse** break the targeted block · **Right mouse** place the selected block.
- **1–9** select a hotbar slot · **F** toggle flight · **F4** switch first/third person.
- **F5** save · **F9** reload the save · **F3** toggle the debug readout · **Esc** pause.

## Shared contract

`prototypes/m17/shared/scenario.json` + `shared/fixture/world.json` define the seed and
the first 16³ chunk used by the cross-engine contract tests; the Godot suite validates
that it can still load the fixture. The scenario's seed is `17017` (the mission text
mentions `17015`; the committed contract is authoritative).

## Inspection flags

`--capture --capture-name=X.png`, `--shots="yaw:pitch[:x,y,z]; …"`, `--hide-hud`,
`--fly`, `--player-at=x,y,z`, `--look=yaw,pitch`, `--render-distance=N`, `--settle=S`,
`--seed=N`, `--fog=<density>` (0 = off), `--no-shadows`, `--straight-to-game`,
`--camera-mode=first|third`, `--camera-distance=N`, `--camera-shoulder=N`,
`--select-slot=N`, `--quit-after=S`. They exist so the rendered game can be
inspected reproducibly; see the progress document for the exact commands used and
the images that were inspected.
