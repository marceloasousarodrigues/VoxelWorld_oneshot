# M22 — Progress and evidence

Art/behaviour contract: `m22-visual-design.md`.

## 1. Repository state at start

- Branch `main`, ahead of `origin/main`.
- Pre-existing uncommitted work preserved untouched:
  - `prototypes/m17/results/godot/game-capture.json` (modified)
  - `tests/test_m16_streaming_budget.py` (modified)
  - many untracked captures, `.verify_tmp*`, `.superpowers/`, `.opencode/` files.
- Godot `4.7.2.stable.mono.official.ed1daf0bf`.
- Existing M17/M18/M19/M20/M21 implementation inspected. The engine and native
  chunk renderer remain the correct architecture; M22 extends them.

## 2. Baseline (before M22 implementation)

Date: 2026-10-19. Seed 17017, radius 4, 1280×720, vsync off.

### Automated suites

| Suite | Command | Result |
| --- | --- | --- |
| Unit | `godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd` | **1693 assertions, exit 0** |
| Integration | `… --script res://scripts/tests/run_integration.gd -- --straight-to-game` | **391 assertions, exit 0** |
| Headless smoke | `… -- --straight-to-game --quit-after=14` | exit 0, `world_hash=7995773462820745781`, 392 chunks, 170492 faces, `faces_hash=6834793821708419232` |

Logs: `.verify_tmp/m22-baseline-unit.txt`, `m22-baseline-integration.txt`,
`m22-baseline-smoke.txt`.

### Performance baseline

| Scenario | p50 ms | p95 ms | p99 ms | worst ms | 1 % low fps | avg draw calls |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| settle | 1.586 | 5.899 | 11.463 | 70.72 | 50.6 | 332.3 |
| look | 1.563 | 3.504 | 6.665 | 79.835 | 87.6 | 487.6 |
| walk | 1.561 | 5.113 | 8.720 | 72.902 | 72.3 | 296.5 |

Reports: `results/godot/m22-before-settle.json`, `m22-before-look.json`,
`m22-before-walk.json`.

### Baseline captures inspected

- `results/godot/m22-baseline-normal-noon.png`
- `results/godot/m22-baseline-close-noon.png`
- `results/godot/m22-baseline-wide-noon.png`

Observed defects (pre-M22):

1. **Vegetation is one repeated green mass.** Oak/pine crowns read as uniform
   green cubes; no flowers, bushes or birch/blossom variety. The wide view is
   almost entirely foliage with little sky and no colour accents.
2. **The showcase has no architecture.** Only a plaza, table, furnace, brick
   pillar and material pads; no building, roof, fence, bridge or inhabited
   settlement detail.
3. **Ground material scale/repetition.** The stone-brick plaza uses one
   1 m texture repeatedly and dominates the close view; there is no path or
   edge treatment that integrates it with the terrain.
4. **Washed-out distance.** The wide capture's sky/horizon is white and the
   middle distance loses colour; fog is too strong for the intended bright,
   colourful look.
5. **Flat canopy lighting.** Dense crowns block most sky, and the remaining
   ground is lit evenly; settlement lighting does not exist.
6. Pre-existing, not fixed by baseline: no live rotating-camera video evidence;
   no human keyboard/mouse play-through.

No baseline test failures. The baseline hash is unchanged from M21, so all
currently recorded evidence is valid for the starting state.
