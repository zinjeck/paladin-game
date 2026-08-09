extends RefCounted
class_name CityCitizenRegistryState

# Settlement-owned mutable core citizen registry state for one CITY.
#
# CityCitizenRegistrySystem owns registry lookup, index repair, and version
# invalidation. Spatial ownership is isolated in CityCitizenSpatialState,
# movement runtime in CityCitizenMovementRuntimeState, and task runtime in
# CityCitizenTaskRuntimeState. Keep this class strictly data-only.

var citizens: Array = []
var citizen_index_by_id: Dictionary = {}
var next_citizen_id: int = 1
var citizen_version: int = 0
