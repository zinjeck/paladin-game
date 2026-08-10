extends RefCounted
class_name CityCitizenTaskRuntimeState

# Settlement-owned mutable citizen task-runtime state for one CITY.
#
# Citizen records retain authoritative current-task and haul payload data. This
# owner holds only the active-task processing index and the version that
# invalidates task observers. CityCitizenTaskRuntimeSystem owns task mutation
# and registry behavior; work availability remains in CityWorkState, while
# task selection and execution remain in the focused citizen behavior systems.
# Keep this class strictly data-only.

var active_task_ids: Array[int] = []
var active_task_id_lookup: Dictionary = {}
var citizen_task_version: int = 0
