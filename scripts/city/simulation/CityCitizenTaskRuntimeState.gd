extends RefCounted
class_name CityCitizenTaskRuntimeState

# Settlement-owned mutable citizen task-runtime state for one CITY.
#
# Citizen records retain authoritative current-task and haul payload data. This
# owner holds only the active-task processing index and the version that
# invalidates task observers. Work availability remains in CityWorkState, and
# task selection/execution behavior remains in the existing citizen systems.
#
# WorldData retains its historical compatibility behavior API during this
# ownership-only pass. Keep this class strictly data-only.

var active_task_ids: Array[int] = []
var active_task_id_lookup: Dictionary = {}
var citizen_task_version: int = 0
