extends RefCounted
class_name CityCitizenSpatialState

# Settlement-owned mutable citizen spatial-index state for one CITY.
#
# Citizen records retain the authoritative city_tile_position. This owner holds
# only the derived tile-to-citizen index and the version that invalidates its
# observers. Movement runtime is isolated in CityCitizenMovementRuntimeState,
# while task indexes are isolated in CityCitizenTaskRuntimeState. Pathfinding
# behavior, assignments, and object access-tile caching remain outside this
# state.
#
# WorldData retains the existing spatial behavior during this ownership-only
# pass. Keep this class strictly data-only.

var citizen_ids_by_tile: Dictionary = {}
var citizen_spatial_version: int = 0
