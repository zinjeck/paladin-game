extends RefCounted
class_name CityNavigationState

# Settlement-owned derived navigation cache state for one CITY.
#
# City object records, world tiles, and topology versions remain authoritative
# in their focused owners. This state owns only access-tile memoization derived
# from those inputs. CityNavigationSystem owns all cache behavior and
# invalidation. Keep this class strictly data-only.

var object_access_tile_cache: Dictionary = {}

# One lazily discovered permissive base-land component. The byte-per-tile
# membership map deliberately ignores objects and diagonal corner rules, so it
# can prove disconnection without ever claiming that an actual path exists.
var base_land_component_world: WorldData = null
var base_land_component_world_size: Vector2i = Vector2i.ZERO
var base_land_component_tile_data_version: int = -1
var base_land_component_seed_tile: Vector2i = Vector2i(-1, -1)
var base_land_component_membership: PackedByteArray = PackedByteArray()
var base_land_component_boundary_indices: PackedInt32Array = PackedInt32Array()
