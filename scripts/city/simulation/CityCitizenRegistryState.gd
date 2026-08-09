extends RefCounted
class_name CityCitizenRegistryState

# Settlement-owned mutable core citizen registry state for one CITY.
#
# This pass relocates only the four registry fields below. Citizen record
# schema and embedded needs, inventory, employment, movement, and task behavior
# remain unchanged and await their own focused boundaries. Spatial ownership is
# isolated in CityCitizenSpatialState, and movement runtime is isolated in
# CityCitizenMovementRuntimeState. Task runtime remains outside this owner for
# its dedicated pass.
#
# WorldData retains the existing citizen behavior during this ownership-only
# pass. Keep this class strictly data-only.

var citizens: Array = []
var citizen_index_by_id: Dictionary = {}
var next_citizen_id: int = 1
var citizen_version: int = 0
