# Paladin rendering invariants

These rules are intentional architecture, not temporary optimizations.

## Map modes

- World and city map-mode textures are prepared as one complete, atomic cache.
- No map mode may be generated incrementally across gameplay frames.
- Switching map modes must be a cached texture swap, not a generation boundary.
- A partial cache must never be published or stored.

## World and city screens

- The active world and city renderers remain owned by the same `GameSession` instance.
- Switching between them changes visibility and processing state. It must not replace or reload either scene.
- First-city CPU preparation may run while the world remains interactive, but the city is revealed only after its complete map atlas is ready.

## Redraw policy

- Static terrain and natural features use retained rendering nodes rather than whole-layer custom redraws.
- `queue_redraw()` is restricted to the coalescing `CityRenderLayer` boundary and controls whose custom geometry genuinely changed.
- Selection, hover, debugging, and simulation invalidations must target only the affected render layer.
- `ci/audit_gdscript.py` enforces the approved `queue_redraw()` call sites and rejects regressions.

## Validation

- Godot import must compile the persistent world, city, session, and test boundaries before the pull request can pass.
- Automated tests must prove that all map modes are ready together and that repeated world/city switches retain the same scene instances.
