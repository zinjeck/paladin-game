# Pass 11: Remaining WorldData Ownership Audit

Pass 11 re-audited the post-Pass-10 `WorldData` boundary and extracted the last clearly isolated city-local derived cache without crossing into the compatibility-workspace or legacy-backend removal passes.

## Extracted in Pass 11

`city_object_access_tile_cache` was city-local derived navigation state and is now owned by settlement-local `CityNavigationState`. `CityNavigationSystem` owns access-tile cache behavior, lookup, reset, and deterministic access-tile computation. `WorldData` no longer declares the cache, exposes `get_city_object_access_tiles`, or owns the associated sort helper.

The cache is selected by active settlement identity through `WorldPoliticalState.get_current_city_navigation_state()`. A pre-context owner exists only for bootstrap/legacy compatibility and is transferred by identity when the founding City or a converted legacy City adopts the instance-owned backend.

The navigation cache does not participate in `CitySettlementSimulationState.capture_from_world_data()` or `apply_to_world_data()`. Settlement switching therefore selects the correct owner directly instead of copying cache dictionaries through the WorldData workspace.

## Intentionally retained in WorldData after Pass 11

The following categories remain legitimate WorldData responsibilities at this boundary:

- generated world/grid and city-world tile data
- founding-region and world-session metadata
- culture/founding identity data
- immutable city catalog aliases and shared metadata helpers
- global visual/session coordination

The remaining city compatibility workspace is deliberately deferred to Pass 12. This includes `official_city_world`, `official_city_seed`, `player_city_data`, and the remaining capture/apply bridge responsibilities that still depend on them.

`BACKEND_LEGACY_CITY_WORLD_DATA` is deliberately retained for Pass 13, where the legacy city backend is removed only after the compatibility workspace has been eliminated.

## Invariants established by Pass 11

- Access-tile memoization is settlement-local and cannot alias merely because two Cities reuse the same local object ID.
- `CityNavigationState` is data-only; navigation behavior remains in `CityNavigationSystem`.
- Access-tile/pathfinding rules are unchanged.
- Clearing or mutating one City's navigation cache cannot modify another City's cache.
- Founding bootstrap and legacy-backend conversion preserve the exact pre-context navigation owner once rather than cloning it.
- The extracted cache must not return to WorldData or to capture/apply copying. The static architecture audit enforces this boundary.

## Verification

The implementation passed Godot CI run #315 on commit `61a144f004a71568cfbfb799fcc119ce80d069a6`. The final documentation-only commit is separately CI-verified by the PR check before merge readiness.

The verified suite covers:

- static GDScript architecture/resource-path audit
- Godot 4.7.1 project import
- full `scripts/**/*Test.tscn` headless suite
- focused navigation-state bootstrap/adoption and A/B/A settlement isolation with equal settlement-local object IDs
