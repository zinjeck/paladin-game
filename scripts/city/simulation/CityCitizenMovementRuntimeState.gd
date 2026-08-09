extends RefCounted
class_name CityCitizenMovementRuntimeState

# Settlement-owned mutable citizen movement-runtime state for one CITY.
#
# Citizen records retain authoritative movement paths, progress, destinations,
# and positions. This owner holds only the active-mover index, transient visual
# event buffer, visual tick identity, and the version that invalidates movement
# observers. Movement/pathfinding behavior remains in its existing systems;
# citizen task runtime lives in CityCitizenTaskRuntimeState, and object
# access-tile caching remains separate.
#
# WorldData retains the historical compatibility behavior API during this
# ownership-only pass. Keep this class strictly data-only.

var active_mover_ids: Array[int] = []
var active_mover_id_lookup: Dictionary = {}
var citizen_movement_visual_events: Array = []
var citizen_movement_visual_tick_index: int = -1
var citizen_movement_version: int = 0
