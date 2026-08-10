# Pass 11: Remaining city-specific WorldData audit

Baseline: `main` after Pass 10 merge commit `63e2a1328eff7df0b0f46e2e0d0e58dc132d2835`.

This pass is an architecture audit and targeted cleanup. It does not remove the capture/apply workspace or the legacy city backend; those remain Passes 12 and 13.

## Fresh classification

### Genuine world/session-level responsibility

These remain legitimate in `WorldData` during Pass 11:

- generated world grid data (`width`, `height`, `seed`, `tiles`, tile-data versions)
- world-save/founding-region selection and scene-return metadata
- world map / city map `WorldData` objects used as generated map data
- culture registry and founding culture identity
- global visual/session cache coordination
- immutable constants and compatibility aliases into catalogs

### Settlement-local simulation already extracted

These must continue resolving through focused settlement-local owners and must not be reintroduced into `WorldData`:

- completed objects / occupancy
- resource accounting
- citizen registry
- citizen spatial state
- citizen movement runtime
- citizen task runtime
- personal inventory / needs mutation boundaries
- housing / job assignment invalidation
- workplace invalidation / staffing policy
- work
- logistics
- construction

### Remaining city-local cache to retire from WorldData

`city_object_access_tile_cache` is derived navigation/topology cache state. Previous passes intentionally left it out of citizen spatial and movement ownership because it is not citizen state. Pass 11 will move its physical ownership to the active `CitySettlementSimulationState` and make `CityNavigationSystem` the behavioral/cache API owner. The cache is derived and may be discarded/rebuilt across bootstrap transitions; it must never leak between City A and City B.

Required invariants:

- City A and City B have independent access-tile caches even when local object IDs and version values match.
- settlement switching selects the matching cache by settlement identity instead of copying it through `WorldData`.
- object-version, map tile-data-version, world-instance, and footprint-hash invalidation behavior remains unchanged.
- reset/new-game paths clear the relevant cache without clearing another settlement.

### Legacy workspace fields deliberately retained for Pass 12

The following are already mirrored by `CitySettlementSimulationState` but are still applied/captured through the compatibility workspace:

- `official_city_world` <-> `city_world`
- `official_city_seed` <-> `city_seed`
- `player_city_data` <-> `city_runtime_data`

Pass 11 will audit their callers but will not prematurely remove the bridge. Pass 12 owns removal of `capture_from_world_data()` / `apply_to_world_data()` and the active-city workspace model.

### Legacy backend deliberately retained for Pass 13

`SettlementSimulationContext.BACKEND_LEGACY_CITY_WORLD_DATA` remains compatibility-only until Pass 13 proves no legitimate record, fixture, migration path, or bootstrap path depends on it.

## Pass 11 boundary

1. Extract `city_object_access_tile_cache` from `WorldData` ownership.
2. Route access-tile cache behavior through `CityNavigationSystem` while preserving compatibility only where necessary.
3. Remove access-cache capture/apply copying from `CitySettlementSimulationState`.
4. Add permanent architecture guards preventing the cache from returning to `WorldData`.
5. Add focused bootstrap/isolation/regression coverage.
6. Run static audit, Godot 4.7.1 import, all `scripts/**/*Test.tscn`, and main-scene boot.
7. Leave the three legacy workspace fields above for Pass 12 and the legacy backend for Pass 13.

No gameplay balance or pathfinding-rule changes belong in this pass.
