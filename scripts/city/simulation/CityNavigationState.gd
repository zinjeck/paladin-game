extends RefCounted
class_name CityNavigationState

# Settlement-owned derived navigation cache state for one CITY.
#
# City object records, world tiles, and topology versions remain authoritative
# in their focused owners. This state owns only access-tile memoization derived
# from those inputs. CityNavigationSystem owns all cache behavior and
# invalidation. Keep this class strictly data-only.

var object_access_tile_cache: Dictionary = {}
