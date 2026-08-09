extends RefCounted
class_name CityCitizenMovementRuntimeState

# Settlement-owned mutable citizen movement-runtime state for one CITY.
#
# Citizen records retain authoritative movement paths, progress, destinations,
# and positions. This owner holds only the active-mover index, transient visual
# event buffer, visual tick identity, and the version that invalidates movement
# observers. CityCitizenMovementRuntimeSystem owns movement orders, atomic
# commits, and this runtime index; CitizenMovementSystem computes ticks and
# CityNavigationSystem owns traversal policy. Citizen task runtime lives in
# CityCitizenTaskRuntimeState, and object access-tile caching remains separate.
# Keep this class strictly data-only.

var active_mover_ids: Array[int] = []
var active_mover_id_lookup: Dictionary = {}
var citizen_movement_visual_events: Array = []
var citizen_movement_visual_tick_index: int = -1
var citizen_movement_version: int = 0
