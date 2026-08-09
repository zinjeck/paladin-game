extends RefCounted
class_name CityResourceAccountingState

# Settlement-owned mutable resource/container accounting state for one CITY.
#
# Physical quantities remain authoritative where they actually exist: completed
# object containers, citizen inventories, logistics ground piles, and
# construction-delivered materials. This state owns only the settlement-level
# aggregate cache, cache stamp, and focused change versions used to account for
# those physical stores.
#
# CityResourceAccountingSystem governs aggregate/cache behavior while
# CityResourceContainerSystem governs one-container queries and mutations.
# Keep this class strictly data-only.

var owned_resource_amount_cache: Dictionary = {}
var owned_resource_amount_cache_container_version: int = -1
var container_version: int = 0
var public_storage_version: int = 0
